const list = document.getElementById("list");
const form = document.getElementById("add-form");
const input = document.getElementById("title");
const errorEl = document.getElementById("error");
const summary = document.getElementById("summary");

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return res.status === 204 ? null : res.json();
}

function showError(err) {
  errorEl.textContent = err ? err.message : "";
  errorEl.hidden = !err;
}

function render(todos) {
  list.replaceChildren();
  for (const todo of todos) {
    const li = document.createElement("li");
    li.className = todo.done ? "done" : "";

    const label = document.createElement("label");
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = todo.done;
    box.addEventListener("change", () => run(() => api("PATCH", `/api/todos/${todo.id}`, { done: box.checked })));
    const text = document.createElement("span");
    text.textContent = todo.title;
    label.append(box, text);

    const del = document.createElement("button");
    del.className = "delete";
    del.textContent = "\u00d7";
    del.title = "Delete";
    del.addEventListener("click", () => run(() => api("DELETE", `/api/todos/${todo.id}`)));

    li.append(label, del);
    list.append(li);
  }
  const open = todos.filter((t) => !t.done).length;
  summary.textContent = todos.length ? `${open} of ${todos.length} remaining` : "Nothing to do. Add a todo above.";
}

async function refresh() {
  render(await api("GET", "/api/todos"));
}

async function run(action) {
  try {
    await action();
    showError(null);
  } catch (err) {
    showError(err);
  }
  try {
    await refresh();
  } catch (err) {
    showError(err);
  }
}

form.addEventListener("submit", (e) => {
  e.preventDefault();
  const title = input.value.trim();
  if (!title) return;
  run(async () => {
    await api("POST", "/api/todos", { title });
    input.value = "";
  });
});

run(async () => {});
