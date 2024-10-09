# README

## Project Setup Guide

This guide will help you set up the environment and run the schema for the external database.

### Prerequisites

- Docker
- Docker Compose
- PostgreSQL

### Step 1: Clone the Repository

First, clone the repository

```bash
git clone <repository-url>
cd <repository-directory>
```

### Step 2: Create a `.env` File

Create a `.env` file in the root of the project with the following content:

```env
ENVIO_PG_HOST=localhost
ENVIO_PG_PORT=5434
ENVIO_PG_USER=postgres
ENVIO_POSTGRES_PASSWORD=postgres
ENVIO_PG_DATABASE=postgres


LOG_STRATEGY="console-pretty"
LOG_LEVEL=trace
TUI_OFF="true"
```

- `LOG_STRATEGY="console-pretty"`: This setting configures the logging strategy to output logs in a pretty format to the console, making them easier to read during development.
- `LOG_LEVEL=trace`: This sets the log level to `trace`, which is the most verbose level, capturing detailed information for debugging.
- `TUI_OFF="true"`: This disables the Text User Interface (TUI), which might be useful if you prefer to see logs directly in the console without any additional UI elements.

### Step 3: Run the Schema

To set up the database schema, run the `schema.sql` file against your PostgreSQL database. You can do this using the `psql` command-line tool or any PostgreSQL client.

#### Using `psql` Command-Line Tool

```bash
psql -U postgres -d postgres -h localhost -p 5434 -a -f schema.sql
```

This command connects to the PostgreSQL database with the specified credentials, switches to the `postgres` user, and executes the `schema.sql` file.

### Step 4: Start the Application

```bash
yarn codegen
yarn dev
```
