set -euo pipefail
# Runs on every branch before it is merged, on a machine that has nothing but
# Docker. Building the image compiles the COBOL (any compiler warning fails
# it); the end-to-end test then runs that image against PostgreSQL.
docker build --platform linux/amd64 -t todo-demo:verify .
bash test/e2e.sh todo-demo:verify
# The page's upload image (Dockerfile.site).
docker build --platform linux/amd64 -f Dockerfile.site -t todo-demo-site:verify .
