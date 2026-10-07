package main

import (
	"context"
	"errors"
	"time"
)

// Todo is a single todo item.
type Todo struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	Done      bool      `json:"done"`
	CreatedAt time.Time `json:"createdAt"`
}

// ErrNotFound is returned when a todo does not exist.
var ErrNotFound = errors.New("not found")

// TodoStore persists todos.
type TodoStore interface {
	List(ctx context.Context) ([]Todo, error)
	Create(ctx context.Context, title string) (Todo, error)
	SetDone(ctx context.Context, id int64, done bool) (Todo, error)
	Delete(ctx context.Context, id int64) error
}
