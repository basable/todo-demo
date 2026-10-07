package main

import (
	"encoding/json"
	"errors"
	"io/fs"
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"
)

const maxTitleLen = 200

func newMux(st TodoStore, static fs.FS) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.Write([]byte("OK"))
	})

	mux.HandleFunc("GET /api/todos", func(w http.ResponseWriter, r *http.Request) {
		todos, err := st.List(r.Context())
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, todos)
	})

	mux.HandleFunc("POST /api/todos", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Title string `json:"title"`
		}
		if !decode(w, r, &body) {
			return
		}
		title := strings.TrimSpace(body.Title)
		if title == "" || utf8.RuneCountInString(title) > maxTitleLen {
			writeError(w, http.StatusBadRequest, "title must be 1-200 characters")
			return
		}
		t, err := st.Create(r.Context(), title)
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, t)
	})

	mux.HandleFunc("PATCH /api/todos/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := parseID(w, r)
		if !ok {
			return
		}
		var body struct {
			Done *bool `json:"done"`
		}
		if !decode(w, r, &body) {
			return
		}
		if body.Done == nil {
			writeError(w, http.StatusBadRequest, "done is required")
			return
		}
		t, err := st.SetDone(r.Context(), id, *body.Done)
		if errors.Is(err, ErrNotFound) {
			writeError(w, http.StatusNotFound, "todo not found")
			return
		} else if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, t)
	})

	mux.HandleFunc("DELETE /api/todos/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := parseID(w, r)
		if !ok {
			return
		}
		err := st.Delete(r.Context(), id)
		if errors.Is(err, ErrNotFound) {
			writeError(w, http.StatusNotFound, "todo not found")
			return
		} else if err != nil {
			serverError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	mux.Handle("GET /", http.FileServerFS(static))
	return mux
}

func parseID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func serverError(w http.ResponseWriter, err error) {
	log.Printf("error: %v", err)
	writeError(w, http.StatusInternalServerError, "internal error")
}
