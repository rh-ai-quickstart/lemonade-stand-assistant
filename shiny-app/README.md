# Shiny App

R Shiny chat interface for the Lemonade Stand Assistant demo.

## Features

- Interactive chat UI with Red Hat branding
- Integration with vLLM API endpoint
- JSON-based detection handling for input/output monitoring

## Requirements

- R 4.4.2+
- Required packages: `shiny`, `shinychat`, `ellmer`, `bslib`, `httr2`, `jsonlite`

## Running Locally

```r
source("app.r")
```

## Podman Build

```bash
podman build -f Containerfile -t shiny-app .
podman run -p 8080:8080 shiny-app
```

Access the app at `http://localhost:8080`
