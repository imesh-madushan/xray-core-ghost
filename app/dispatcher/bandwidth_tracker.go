package dispatcher

import (
	"context"
	"encoding/json"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/common/buf"
	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/transport"
)

// BandwidthRecord holds the tracked bandwidth data for a connection
type BandwidthRecord struct {
	User       string    `json:"user"`
	Domain     string    `json:"domain"`
	InboundTag string    `json:"inboundTag"`
	UpBytes    int64     `json:"upBytes"`
	DownBytes  int64     `json:"downBytes"`
	Duration   int64     `json:"duration"`
	Timestamp  time.Time `json:"timestamp"`
}

// CountingReader wraps a buf.Reader and counts bytes read
type CountingReader struct {
	reader    buf.TimeoutReader
	downBytes int64
	startTime time.Time
	closed    int32
	mu        sync.Mutex
}

// NewCountingReader creates a new CountingReader wrapping the given reader
func NewCountingReader(reader buf.TimeoutReader) *CountingReader {
	return &CountingReader{
		reader:    reader,
		startTime: time.Now(),
	}
}

// ReadMultiBuffer implements buf.Reader
func (r *CountingReader) ReadMultiBuffer() (buf.MultiBuffer, error) {
	mb, err := r.reader.ReadMultiBuffer()
	if !mb.IsEmpty() {
		atomic.AddInt64(&r.downBytes, int64(mb.Len()))
	}
	return mb, err
}

// ReadMultiBufferTimeout implements buf.TimeoutReader
func (r *CountingReader) ReadMultiBufferTimeout(timeout time.Duration) (buf.MultiBuffer, error) {
	mb, err := r.reader.ReadMultiBufferTimeout(timeout)
	if !mb.IsEmpty() {
		atomic.AddInt64(&r.downBytes, int64(mb.Len()))
	}
	return mb, err
}

// Interrupt implements common.Interruptible
func (r *CountingReader) Interrupt() {
	if timeoutReader, ok := r.reader.(interface{ Interrupt() }); ok {
		timeoutReader.Interrupt()
	}
}

// GetDownBytes returns the total bytes read
func (r *CountingReader) GetDownBytes() int64 {
	return atomic.LoadInt64(&r.downBytes)
}

// GetDuration returns the duration since this reader was created
func (r *CountingReader) GetDuration() int64 {
	return int64(time.Since(r.startTime).Seconds())
}

// Close closes the reader
func (r *CountingReader) Close() error {
	if !atomic.CompareAndSwapInt32(&r.closed, 0, 1) {
		return nil // Already closed
	}

	if closer, ok := r.reader.(interface{ Close() error }); ok {
		return closer.Close()
	}
	return nil
}

// CountingWriter wraps a buf.Writer and counts bytes written
type CountingWriter struct {
	writer    buf.Writer
	upBytes   int64
	startTime time.Time
	closed    int32
	mu        sync.Mutex
}

// NewCountingWriter creates a new CountingWriter wrapping the given writer
func NewCountingWriter(writer buf.Writer) *CountingWriter {
	return &CountingWriter{
		writer:    writer,
		startTime: time.Now(),
	}
}

// WriteMultiBuffer implements buf.Writer
func (w *CountingWriter) WriteMultiBuffer(mb buf.MultiBuffer) error {
	if !mb.IsEmpty() {
		atomic.AddInt64(&w.upBytes, int64(mb.Len()))
	}
	return w.writer.WriteMultiBuffer(mb)
}

// GetUpBytes returns the total bytes written
func (w *CountingWriter) GetUpBytes() int64 {
	return atomic.LoadInt64(&w.upBytes)
}

// GetDuration returns the duration since this writer was created
func (w *CountingWriter) GetDuration() int64 {
	return int64(time.Since(w.startTime).Seconds())
}

// Close implements io.Closer
func (w *CountingWriter) Close() error {
	if !atomic.CompareAndSwapInt32(&w.closed, 0, 1) {
		return nil // Already closed
	}

	return common.Close(w.writer)
}

// Interrupt implements common.Interruptible
func (w *CountingWriter) Interrupt() {
	common.Interrupt(w.writer)
}

// BandwidthEmitter sends bandwidth records to a Unix socket
type BandwidthEmitter struct {
	socketPath string
	mu         sync.Mutex
}

// NewBandwidthEmitter creates a new BandwidthEmitter
func NewBandwidthEmitter(socketPath string) *BandwidthEmitter {
	return &BandwidthEmitter{
		socketPath: socketPath,
	}
}

// Emit sends a bandwidth record to the Unix socket
func (e *BandwidthEmitter) Emit(record *BandwidthRecord) {
	go func() {
		e.mu.Lock()
		defer e.mu.Unlock()

		conn, err := net.DialTimeout("unix", e.socketPath, 5*time.Second)
		if err != nil {
			errors.LogWarning(context.Background(), "Failed to connect to bandwidth socket: ", err)
			return
		}
		defer conn.Close()

		data, err := json.Marshal(record)
		if err != nil {
			errors.LogWarning(context.Background(), "Failed to marshal bandwidth record: ", err)
			return
		}

		data = append(data, '\n')
		_, err = conn.Write(data)
		if err != nil {
			errors.LogWarning(context.Background(), "Failed to write bandwidth record: ", err)
		}
	}()
}

// ConnectionBandwidthData holds the aggregated bandwidth data for a complete connection
type ConnectionBandwidthData struct {
	reader     *CountingReader
	writer     *CountingWriter
	user       string
	domain     string
	inboundTag string
	startTime  time.Time
}

// NewConnectionBandwidthData creates tracking data for a connection
func NewConnectionBandwidthData(reader *CountingReader, writer *CountingWriter, user, domain, inboundTag string) *ConnectionBandwidthData {
	return &ConnectionBandwidthData{
		reader:     reader,
		writer:     writer,
		user:       user,
		domain:     domain,
		inboundTag: inboundTag,
		startTime:  time.Now(),
	}
}

// BuildRecord creates the final bandwidth record with collected metrics
func (d *ConnectionBandwidthData) BuildRecord() *BandwidthRecord {
	return &BandwidthRecord{
		User:       d.user,
		Domain:     d.domain,
		InboundTag: d.inboundTag,
		UpBytes:    d.writer.GetUpBytes(),
		DownBytes:  d.reader.GetDownBytes(),
		Duration:   int64(time.Since(d.startTime).Seconds()),
		Timestamp:  time.Now(),
	}
}

// GlobalBandwidthEmitter is the global emitter instance
var GlobalBandwidthEmitter *BandwidthEmitter

func getCountingReader(link *transport.Link) *CountingReader {
	if link == nil || link.Reader == nil {
		return nil
	}

	if reader, ok := link.Reader.(*CountingReader); ok {
		return reader
	}

	if cached, ok := link.Reader.(*cachedReader); ok {
		if reader, ok := cached.reader.(*CountingReader); ok {
			return reader
		}
	}

	return nil
}

func getCountingWriter(link *transport.Link) *CountingWriter {
	if link == nil || link.Writer == nil {
		return nil
	}

	if writer, ok := link.Writer.(*CountingWriter); ok {
		return writer
	}

	return nil
}

// InitBandwidthEmitter initializes the global emitter with the socket path
func InitBandwidthEmitter(socketPath string) {
	if socketPath == "" {
		socketPath = "/tmp/xray_bandwidth.sock"
	}
	GlobalBandwidthEmitter = NewBandwidthEmitter(socketPath)
}

// EmitBandwidth emits a bandwidth record for the given link if it contains counting wrappers
func EmitBandwidth(inbound *transport.Link, outbound *transport.Link, domain string, user string, inboundTag string) {
	if GlobalBandwidthEmitter == nil {
		InitBandwidthEmitter("")
	}

	if user == "" {
		return
	}

	countingReader := getCountingReader(outbound)
	countingWriter := getCountingWriter(inbound)
	if countingWriter == nil {
		countingWriter = getCountingWriter(outbound)
	}

	// Only emit if we have both reader and writer tracking
	if countingReader != nil && countingWriter != nil {
		data := NewConnectionBandwidthData(
			countingReader,
			countingWriter,
			user,
			domain,
			inboundTag,
		)
		record := data.BuildRecord()
		GlobalBandwidthEmitter.Emit(record)
	}
}
