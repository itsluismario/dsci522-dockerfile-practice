# dsci522-dockerfile-practice

Docker image with Python 3.14, `cowsay` and `numpy`, managed with [uv](https://docs.astral.sh/uv/). The image is built and published to Docker Hub by GitHub Actions.

**Docker Hub:** https://hub.docker.com/r/itsluismario/dsci522-dockerfile-practice

```bash
docker run --rm itsluismario/dsci522-dockerfile-practice uv run python -c "import cowsay, numpy; cowsay.cow('hi')"
```

---

# Learning notes: Docker

Notes on Docker basics: images, containers, the Dockerfile, volumes and Docker Compose, with R (`rocker/r-ver`) and Python (`uv`).

---

## 1. Core concepts

| | What it is | When it's defined |
|---|---|---|
| **Dockerfile** | The recipe | You write it |
| **Image** | Packaged dependencies and versions | `docker build` |
| **Container** | The image running | `docker run` |
| **Ports** | Connection between your machine and the container | `docker run -p` |
| **Volume** | A folder on your machine connected to the container | `docker run -v` |

- An **image** is like a *class* and a **container** is like an *object*: you can start many containers from one image.
- Each Dockerfile instruction creates a **layer**. Docker caches layers that haven't changed, so **order matters**: what changes least goes first.
- A container **lives as long as its main process lives**, the `CMD` command. When that process ends, the container stops.
- Anything created inside a container **is lost when the container is removed**. Anything permanent goes in the Dockerfile, and data goes in volumes.
- **Client and daemon**: the `docker` command only sends instructions. The engine that builds and runs is the daemon, which **Docker Desktop** starts on a Mac.

---

## 2. Dockerfile with R (`rocker/r-ver`)

```dockerfile
FROM rocker/r-ver:4.6.2

CMD ["R"]
```

- `rocker/r-ver` pins the R version, and the CRAN repository is pinned to a date. This makes it reproducible.
- Always use an exact version, never `latest`.
- A fuller example:

```dockerfile
FROM rocker/r-ver:4.6.2

RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev libssl-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN install2.r --error --skipinstalled dplyr readr ggplot2

WORKDIR /app
COPY script.R .
CMD ["Rscript", "script.R"]
```

### Main instructions

| Instruction | What it does |
|---|---|
| `FROM` | Base image (always comes first) |
| `RUN` | Runs a command **at build time** |
| `WORKDIR` | Working folder inside the image |
| `COPY` | Copies files from your machine into the image |
| `ENV` | Sets environment variables |
| `EXPOSE` | Only **documents** a port; it doesn't open it |
| `CMD` | Default command **at run time** |

---

## 3. Dockerfile with Python (`uv`)

```dockerfile
FROM ubuntu:24.04

COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /bin/

WORKDIR /workspace

COPY pyproject.toml uv.lock .python-version ./

# Environment outside /workspace, so a volume doesn't hide it
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

RUN uv sync --locked
```

To also copy your code and set a default command:

```dockerfile
COPY . .
CMD ["uv", "run", "python", "hello.py"]
```

### `pyproject.toml` and `uv.lock`

- **`pyproject.toml`**: you edit it. It says *which* packages you need.
- **`uv.lock`**: uv generates it. It pins the **exact version** of everything, including your dependencies' dependencies.
- The lockfile is created **on your Mac**, not inside Docker:

```bash
uv init            # creates pyproject.toml and .python-version
uv add cowsay==6.1 # adds the dependency and creates/updates uv.lock
uv lock            # regenerates uv.lock if you edited pyproject.toml by hand
```

- `uv sync --locked` installs exactly what's in the lockfile, and fails if it doesn't match `pyproject.toml`.
- With `add-bounds = "exact"` under `[tool.uv]`, `uv add` writes packages with `==`.
- Your Mac's `.venv` **doesn't work** on Linux, because some packages contain parts compiled for macOS. That's why it's created inside the image.

### `.gitignore` vs `.dockerignore`

- `.gitignore`: files git doesn't upload to GitHub (for example `.venv/`, secrets).
- `.dockerignore`: files Docker doesn't copy into the image:

```
.git/
.venv/
__pycache__/
*.pyc
.DS_Store
```

---

## 4. `COPY` and paths

```
COPY  hello.py   ./
      └ source ┘ └ destination ┘
```

- **Source**: a path on your Mac, relative to the build context (the `.` in `docker build`).
- **Destination**: a path inside the image, relative to `WORKDIR`.
- `./` means "the current folder" = `WORKDIR`. With `WORKDIR /workspace`, `./` is the same as `/workspace/`.
- A trailing `/` means the destination is a folder. It's required when copying several files.
- Use **`COPY . .`** rather than `COPY * ./`: with `*`, Docker copies the **contents** of folders and loses the structure.

---

## 5. Volumes (`--volume` / `-v`)

```bash
docker run --rm -it --volume "$(pwd)":/workspace my-image
#                            └ your Mac ┘ └ container ┘
```

- They connect a folder on your Mac to one in the container, **live and in both directions**.
- `COPY` acts at build time and makes a fixed copy. `--volume` acts at run time and connects the folder live.
- On a Mac the path must be absolute, which is why `"$(pwd)"` is used.

### A volume **hides** the folder it's mounted on

The **picture frame** analogy: the volume puts the photo of your Mac's folder *in front of* whatever was in that folder. What's behind isn't deleted, but you can't see it anymore.

```
❌ Wrong                       ✅ Right
/                              /
├── workspace/  ← volume       ├── workspace/  ← volume
│   └── .venv/  ← hidden       │   └── hello.py
└── opt/                       └── opt/
                                   └── venv/   ← untouched
```

**Rule:** everything *inside* the folder you mount is hidden; everything *outside* it isn't. That's why `ENV UV_PROJECT_ENVIRONMENT=/opt/venv` is used. It can be any path outside `/workspace`; `/opt` is just the convention for add-on software.

---

## 6. Docker Compose

- **The Dockerfile** says **how to build** the image ("what's inside?").
- **Compose** says **how to run** containers ("how do I start it?"): ports, volumes and names.
- Compose doesn't replace the Dockerfile; `build: .` uses it. It's your `docker run` written in a file, and it can start several services together.

```yaml
services:
  analysis-env:
    build: .                    # docker build .
    image: 2026-11-24-docker    # --tag
    ports:
      - "127.0.0.1:2222:22"     # -p (only reachable from your computer)
    volumes:
      - .:/workspace            # -v  your_Mac:container
```

- Volumes need **two paths** (`source:destination`).
- Put ports **in quotes**.
- Port 22 is SSH: it's only useful if the image has an SSH server.

```bash
docker compose up --build                 # build and start
docker compose up -d                      # in the background
docker compose run --rm analysis-env bash # a shell inside
docker compose down                       # stop and remove
```

---

## 7. GitHub Actions and Docker Hub

- The workflow `.github/workflows/publish-dockerhub.yml` builds the image and pushes it to Docker Hub with two tags: `latest` and `sha-` plus the first 7 characters of the commit.
- It runs by hand (**Actions → Run workflow**) or on a push that changes the `Dockerfile`, `uv.lock`, `renv.lock` or the workflow file.
- It needs two **repository secrets** (**Settings → Secrets and variables → Actions**), each one a separate secret:

| Name | Value |
|---|---|
| `DOCKER_USERNAME` | Docker Hub username (lowercase) |
| `DOCKER_PASSWORD` | Docker Hub access token with **Read & Write** (not your password) |

- A token's value is shown **only once**, when it's created. Docker Desktop's "auto-generated" tokens can't be reused.
- Secrets aren't environment variables automatically: the workflow reads them with `${{ secrets.NAME }}`. In the logs they appear as `***`.
- `mkdir -p .github/workflows` creates every missing folder in the path, and doesn't fail if they already exist.

---

## 8. Essential commands

```bash
# Build (from the project folder; the "." is required)
docker build --tag dsci522-test .

# Run
docker run --rm -it dsci522-test                 # interactive; removed on exit
docker run -dit --name my-r lecture3-r:2026-11-14 # in the background

# Connect to a running container
docker attach my-r          # leave without stopping it: Ctrl+P then Ctrl+Q
docker exec -it my-r bash   # a new shell inside

# Inspect and manage
docker images               # images
docker ps / docker ps -a    # containers (running / all)
docker stop | start | rm my-r
docker logs my-r
docker rmi lecture3-r:2026-11-14
docker version              # checks the daemon responds (Server section)
```

### Names and tags: `name:tag`

```
lecture3-r:2026-11-14
└ name ─┘ └── tag ──┘
```

- The **name** says *what* it is; the **tag**, *which version*. Without a tag, Docker uses `latest`.
- Names are made up: they can be anything.
- Rules: **lowercase only**; letters, numbers, `-`, `_` and `.` are allowed; it can't start or end with a separator.

### Flags

- **One dash** for one-letter options: `-i`, `-t`, `-p`, `-v`. They can be combined: `-it`.
- **Two dashes** for full words: `--rm`, `--tag`, `--name`, `--volume`.
- `-it` is needed for interactive programs like R or Python. Without it, the process ends immediately.

---

## 9. Errors I hit and how I fixed them

| Error / symptom | Cause | Fix |
|---|---|---|
| `docker build` does nothing | Missing build context | `docker build --tag name .` (with the `.`) |
| `--tag 2026-11-14-docker.` | The dot was stuck to the name | Separate it with a space: `... 2026-11-14-docker .` |
| `failed to connect to the docker API ... docker.sock` | Docker Desktop wasn't running | `open -a Docker` and wait for it to start |
| `unknown instruction: CMD["R"]` | Missing space | `CMD ["R"]` |
| `-rm` doesn't work | Long option with a single dash | `--rm` |
| Image not found | The name didn't match (day 14 vs 24) | Check with `docker images` and copy `REPOSITORY:TAG` |
| `coway was not found in the package registry` | Typo in the package name | `cowsay==6.1`, or use `uv add` |
| Python can't find packages when using `-v` | The volume hid `/workspace/.venv` | `ENV UV_PROJECT_ENVIRONMENT=/opt/venv` |
| Compose volume `- ./workspace` | It had only one path | `- .:/workspace` |
| Remote URL had `TU_USUARIO` | Placeholder copied as-is | `git remote set-url origin git@github.com:itsluismario/dsci522-dockerfile-practice.git` |
| `deleted by us: Dockerfile` after `git pull` | Local and GitHub histories were unrelated | `git rebase --abort`, then `git pull --no-rebase --allow-unrelated-histories` |
| Only one secret in the list | `DOCKER_USERNAME` wasn't created | Add each secret separately with **New repository secret** |

---

## 10. My questions (and short answers)

1. **Is the image where I define dependencies, versions and ports? Is the container the image running?**
   Yes, the container is the image running. Dependencies are defined in the Dockerfile and packaged into the image, but **ports are connected at run time** (`-p`). `EXPOSE` only documents them.
2. **Why did `docker build` do nothing?**
   You need to `cd` into the folder and pass the context (`.`).
3. **Is `docker build --tag 2026-11-14-docker.` correct?**
   A space is missing before the dot.
4. **How do I see the image I built?**
   `docker images`, or the *Images* tab in Docker Desktop.
5. **What is `lecture3` in `lecture3-r:2026-11-14`?**
   A made-up name for the image. It can be anything, in lowercase.
6. **How do I keep a container running?**
   With `-d`: `docker run -dit --name my-r image`. Then `docker attach` or `docker exec`.
7. **How is `uv.lock` created?**
   On your Mac, with `uv add` or `uv lock`.
8. **What does `./` mean in `COPY hello.py ./`?**
   The current folder inside the image, i.e. `WORKDIR`.
9. **What if I use `COPY * ./`?**
   It copies the files but flattens folders. Prefer `COPY . .` with a `.dockerignore`.
10. **What does `--volume` do?**
    It connects a folder on your Mac to one in the container, live.
11. **On Linux, does the venv have to be in `/opt/venv`?**
    No. It can be any path **outside** the folder you mount.
12. **Should the venv be at the same level as `/workspace` rather than inside it?**
    Yes. It must be outside `/workspace`, for example in `/opt/venv`, because `/opt` and `/workspace` both hang directly off `/`.
13. **What's the difference between Docker Compose and the Dockerfile?**
    The Dockerfile **builds** the image; Compose **runs** containers with their configuration (ports, volumes), and uses the Dockerfile through `build: .`.
14. **Do I also need R for the assignment?**
    No. The assignment asks for **either** uv (Python) **or** renv (R), not both.
15. **Can I reuse an existing Docker Hub token?**
    No. Its value is shown only once. Create a new one with **Read & Write**.
16. **Are repository secrets environment variables?**
    Not automatically. The workflow reads them with `${{ secrets.NAME }}`, and can turn them into environment variables with `env:`.
17. **Does the assignment ask for anything in the README?**
    No, only that a README exists.
