# WorkMan

Project Management System
Prompt: Build a simple Project Management System for projects, teams, tasks, milestones, priorities, deadlines, comments, and project status.

Built with [AppWand](https://appwand.dev). The code is plain Flutter and Express, with no AppWand runtime.

| Part | Folder | Stack |
| --- | --- | --- |
| App | `app/` | Flutter, Riverpod, go_router, dio |
| API | `api/` | Node.js, Express, Sequelize, Zod |
| Database | `database/` | PostgreSQL |

## Getting started

### Database

Create an empty PostgreSQL database and load the tables:

```bash
psql -d <database> -f database/schema.sql
```

### API

```bash
cd api
npm install
cp .env.example .env   # then fill in DB_USER, DB_PASSWORD, DB_NAME and JWT_SECRET
npm start
```

It listens on port 8842 (`PORT` in `.env`).

### App

```bash
cd app
flutter pub get
flutter run
```

The app calls `http://localhost:8842/api`. To use another API, pass its address:

```bash
flutter run --dart-define=API_URL=https://example.com/api
```
