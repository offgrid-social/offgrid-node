package main

import (
	"encoding/json"
	"io"
	"log"
	"time"
)

type Logger struct {
	out *log.Logger
}

func NewLogger(w io.Writer) *Logger {
	return &Logger{out: log.New(w, "", 0)}
}

func (l *Logger) Info(event string, fields map[string]any) {
	l.write("info", event, fields)
}

func (l *Logger) Error(event string, fields map[string]any) {
	l.write("error", event, fields)
}

func (l *Logger) write(level string, event string, fields map[string]any) {
	payload := map[string]any{
		"ts":    time.Now().UTC().Format(time.RFC3339Nano),
		"level": level,
		"event": event,
	}
	for k, v := range fields {
		payload[k] = v
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		l.out.Printf(`{"level":"error","event":"logger_marshal_failed","error":"%s"}`, err.Error())
		return
	}
	l.out.Println(string(raw))
}
