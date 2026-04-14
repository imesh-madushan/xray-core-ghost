package dispatcher

import (
	"time"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/common/buf"
	"github.com/xtls/xray-core/features/stats"
)

type SizeStatWriter struct {
	Counter stats.Counter
	Writer  buf.Writer
}

func (w *SizeStatWriter) WriteMultiBuffer(mb buf.MultiBuffer) error {
	if w.Counter != nil && mb != nil {
		w.Counter.Add(int64(mb.Len()))
	}
	return w.Writer.WriteMultiBuffer(mb)
}

func (w *SizeStatWriter) Close() error {
	return common.Close(w.Writer)
}

func (w *SizeStatWriter) Interrupt() {
	common.Interrupt(w.Writer)
}

type SizeStatReader struct {
	Counter stats.Counter
	Reader  buf.Reader
}

func (r *SizeStatReader) ReadMultiBuffer() (buf.MultiBuffer, error) {
	mb, err := r.Reader.ReadMultiBuffer()
	if r.Counter != nil && mb != nil {
		r.Counter.Add(int64(mb.Len()))
	}
	return mb, err
}

func (r *SizeStatReader) ReadMultiBufferTimeout(timeout time.Duration) (buf.MultiBuffer, error) {
	if tr, ok := r.Reader.(buf.TimeoutReader); ok {
		mb, err := tr.ReadMultiBufferTimeout(timeout)
		if r.Counter != nil && mb != nil {
			r.Counter.Add(int64(mb.Len()))
		}
		return mb, err
	}
	return r.ReadMultiBuffer()
}

func (r *SizeStatReader) Interrupt() {
	common.Interrupt(r.Reader)
}