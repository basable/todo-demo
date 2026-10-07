package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// connect retries until the database accepts connections (it may still be starting).
func connect(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	var lastErr error
	for attempt := 1; attempt <= 60; attempt++ {
		pool, err := pgxpool.New(ctx, dsn)
		if err == nil {
			pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
			err = pool.Ping(pingCtx)
			cancel()
			if err == nil {
				return pool, nil
			}
			pool.Close()
		}
		lastErr = err
		log.Printf("waiting for database (attempt %d): %v", attempt, err)
		time.Sleep(2 * time.Second)
	}
	return nil, fmt.Errorf("giving up: %w", lastErr)
}

// PGStore implements TodoStore on PostgreSQL.
type PGStore struct {
	pool *pgxpool.Pool
}

func (s *PGStore) Migrate(ctx context.Context) error {
	_, err := s.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS todos (
		id BIGSERIAL PRIMARY KEY,
		title TEXT NOT NULL,
		done BOOLEAN NOT NULL DEFAULT FALSE,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`)
	return err
}

func (s *PGStore) List(ctx context.Context) ([]Todo, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, title, done, created_at FROM todos ORDER BY created_at, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	todos := []Todo{}
	for rows.Next() {
		var t Todo
		if err := rows.Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt); err != nil {
			return nil, err
		}
		todos = append(todos, t)
	}
	return todos, rows.Err()
}

func (s *PGStore) Create(ctx context.Context, title string) (Todo, error) {
	var t Todo
	err := s.pool.QueryRow(ctx,
		`INSERT INTO todos (title) VALUES ($1) RETURNING id, title, done, created_at`, title,
	).Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt)
	return t, err
}

func (s *PGStore) SetDone(ctx context.Context, id int64, done bool) (Todo, error) {
	var t Todo
	err := s.pool.QueryRow(ctx,
		`UPDATE todos SET done = $2 WHERE id = $1 RETURNING id, title, done, created_at`, id, done,
	).Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, ErrNotFound
	}
	return t, err
}

func (s *PGStore) Delete(ctx context.Context, id int64) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM todos WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
