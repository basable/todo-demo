package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
	"time"
)

type memStore struct {
	todos  []Todo
	nextID int64
}

func (m *memStore) List(ctx context.Context) ([]Todo, error) { return append([]Todo{}, m.todos...), nil }

func (m *memStore) Create(ctx context.Context, title string) (Todo, error) {
	m.nextID++
	t := Todo{ID: m.nextID, Title: title, CreatedAt: time.Now()}
	m.todos = append(m.todos, t)
	return t, nil
}

func (m *memStore) SetDone(ctx context.Context, id int64, done bool) (Todo, error) {
	for i := range m.todos {
		if m.todos[i].ID == id {
			m.todos[i].Done = done
			return m.todos[i], nil
		}
	}
	return Todo{}, ErrNotFound
}

func (m *memStore) Delete(ctx context.Context, id int64) error {
	for i := range m.todos {
		if m.todos[i].ID == id {
			m.todos = append(m.todos[:i], m.todos[i+1:]...)
			return nil
		}
	}
	return ErrNotFound
}

func do(h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestTodoLifecycle(t *testing.T) {
	static := fstest.MapFS{"index.html": {Data: []byte("<html></html>")}}
	h := securityHeaders(newMux(&memStore{}, static))

	if rec := do(h, "POST", "/api/todos", `{"title":"   "}`); rec.Code != 400 {
		t.Fatalf("empty title: got %d", rec.Code)
	}
	rec := do(h, "POST", "/api/todos", `{"title":"buy milk"}`)
	if rec.Code != 201 {
		t.Fatalf("create: got %d", rec.Code)
	}
	if rec := do(h, "PATCH", "/api/todos/1", `{"done":true}`); rec.Code != 200 {
		t.Fatalf("patch: got %d", rec.Code)
	}
	rec = do(h, "GET", "/api/todos", "")
	var todos []Todo
	if err := json.NewDecoder(rec.Body).Decode(&todos); err != nil || len(todos) != 1 || !todos[0].Done {
		t.Fatalf("list: %v %+v", err, todos)
	}
	if rec := do(h, "DELETE", "/api/todos/1", ""); rec.Code != 204 {
		t.Fatalf("delete: got %d", rec.Code)
	}
	if rec := do(h, "DELETE", "/api/todos/1", ""); rec.Code != 404 {
		t.Fatalf("delete missing: got %d", rec.Code)
	}
	rec = do(h, "GET", "/", "")
	if rec.Code != 200 || rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("index: got %d", rec.Code)
	}
}
