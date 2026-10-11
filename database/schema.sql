-- AppWand database export (PostgreSQL)
SET client_min_messages = warning;
SET check_function_bodies = false;

CREATE SEQUENCE IF NOT EXISTS access_permissions_id_seq;
CREATE SEQUENCE IF NOT EXISTS access_roles_id_seq;
CREATE SEQUENCE IF NOT EXISTS access_seeded_id_seq;

CREATE TABLE "access_permissions" (
  "id" bigint DEFAULT nextval('access_permissions_id_seq'::regclass) NOT NULL,
  "role_key" character varying(64) NOT NULL,
  "permission" character varying(160) NOT NULL,
  CONSTRAINT "access_permissions_pkey" PRIMARY KEY (id),
  CONSTRAINT "access_permissions_role_key_permission_key" UNIQUE (role_key, permission)
);

CREATE TABLE "access_roles" (
  "id" bigint DEFAULT nextval('access_roles_id_seq'::regclass) NOT NULL,
  "role_key" character varying(64) NOT NULL,
  "name" character varying(100) NOT NULL,
  "description" character varying(255),
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "access_roles_pkey" PRIMARY KEY (id),
  CONSTRAINT "access_roles_role_key_key" UNIQUE (role_key)
);

CREATE TABLE "access_seeded" (
  "id" bigint DEFAULT nextval('access_seeded_id_seq'::regclass) NOT NULL,
  "name" character varying(190) NOT NULL,
  CONSTRAINT "access_seeded_pkey" PRIMARY KEY (id),
  CONSTRAINT "access_seeded_name_key" UNIQUE (name)
);

CREATE TABLE "comments" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "task_id" integer NOT NULL,
  "user_id" integer,
  "body" text NOT NULL,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "comments_pkey" PRIMARY KEY (id)
);

CREATE TABLE "milestones" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "project_id" integer NOT NULL,
  "title" character varying(200) NOT NULL,
  "description" text,
  "due_date" date NOT NULL,
  "status" character varying(20) DEFAULT 'upcoming'::character varying NOT NULL,
  "reached_at" timestamp without time zone,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "milestones_pkey" PRIMARY KEY (id)
);

CREATE TABLE "project_teams" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "project_id" integer NOT NULL,
  "team_id" integer NOT NULL,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "project_teams_pkey" PRIMARY KEY (id),
  CONSTRAINT "uq_project_teams" UNIQUE (project_id, team_id)
);

CREATE TABLE "projects" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name" character varying(200) NOT NULL,
  "description" text,
  "status" character varying(20) DEFAULT 'planned'::character varying NOT NULL,
  "priority" character varying(20) DEFAULT 'medium'::character varying NOT NULL,
  "start_date" date,
  "deadline" date,
  "manager_id" integer,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "projects_pkey" PRIMARY KEY (id)
);

CREATE TABLE "tasks" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "project_id" integer NOT NULL,
  "milestone_id" integer,
  "title" character varying(200) NOT NULL,
  "description" text,
  "priority" character varying(20) DEFAULT 'medium'::character varying NOT NULL,
  "status" character varying(20) DEFAULT 'todo'::character varying NOT NULL,
  "deadline" date,
  "assignee_id" integer,
  "created_by" integer,
  "completed_at" timestamp without time zone,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "tasks_pkey" PRIMARY KEY (id)
);

CREATE TABLE "team_members" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "team_id" integer NOT NULL,
  "user_id" integer NOT NULL,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "team_members_pkey" PRIMARY KEY (id),
  CONSTRAINT "uq_team_members" UNIQUE (team_id, user_id)
);

CREATE TABLE "teams" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name" character varying(150) NOT NULL,
  "description" text,
  "created_by" integer,
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "teams_pkey" PRIMARY KEY (id)
);

CREATE TABLE "users" (
  "id" integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  "name" character varying(150) NOT NULL,
  "email" character varying(255) NOT NULL,
  "password_hash" character varying(255) NOT NULL,
  "role" character varying(30) DEFAULT 'team_member'::character varying NOT NULL,
  "is_active" boolean DEFAULT true NOT NULL,
  "photo" character varying(255),
  "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updated_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT "users_pkey" PRIMARY KEY (id),
  CONSTRAINT "users_email_key" UNIQUE (email)
);

ALTER TABLE "comments" ADD CONSTRAINT "comments_task_id_fkey" FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;
ALTER TABLE "comments" ADD CONSTRAINT "comments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE "milestones" ADD CONSTRAINT "milestones_project_id_fkey" FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
ALTER TABLE "project_teams" ADD CONSTRAINT "project_teams_project_id_fkey" FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
ALTER TABLE "project_teams" ADD CONSTRAINT "project_teams_team_id_fkey" FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE;
ALTER TABLE "projects" ADD CONSTRAINT "projects_manager_id_fkey" FOREIGN KEY (manager_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_assignee_id_fkey" FOREIGN KEY (assignee_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_milestone_id_fkey" FOREIGN KEY (milestone_id) REFERENCES milestones(id) ON DELETE SET NULL;
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_project_id_fkey" FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;
ALTER TABLE "team_members" ADD CONSTRAINT "team_members_team_id_fkey" FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE;
ALTER TABLE "team_members" ADD CONSTRAINT "team_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE "teams" ADD CONSTRAINT "teams_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX idx_milestones_status ON public.milestones USING btree (status);
CREATE INDEX idx_tasks_created_by ON public.tasks USING btree (created_by);
CREATE INDEX idx_tasks_priority ON public.tasks USING btree (priority);
CREATE INDEX idx_tasks_milestone ON public.tasks USING btree (milestone_id);
CREATE INDEX idx_tasks_status ON public.tasks USING btree (status);
CREATE INDEX idx_projects_status ON public.projects USING btree (status);
CREATE INDEX idx_team_members_user ON public.team_members USING btree (user_id);
CREATE INDEX idx_comments_task ON public.comments USING btree (task_id);
CREATE INDEX idx_tasks_project ON public.tasks USING btree (project_id);
CREATE INDEX idx_tasks_deadline ON public.tasks USING btree (deadline);
CREATE INDEX idx_users_role ON public.users USING btree (role);
CREATE INDEX idx_projects_manager ON public.projects USING btree (manager_id);
CREATE INDEX idx_project_teams_team ON public.project_teams USING btree (team_id);
CREATE INDEX idx_projects_deadline ON public.projects USING btree (deadline);
CREATE INDEX idx_milestones_project ON public.milestones USING btree (project_id);
CREATE INDEX idx_teams_created_by ON public.teams USING btree (created_by);
CREATE INDEX idx_tasks_assignee ON public.tasks USING btree (assignee_id);
CREATE INDEX idx_comments_user ON public.comments USING btree (user_id);
CREATE INDEX idx_milestones_due_date ON public.milestones USING btree (due_date);
ALTER SEQUENCE access_permissions_id_seq OWNED BY "access_permissions"."id";
ALTER SEQUENCE access_roles_id_seq OWNED BY "access_roles"."id";
ALTER SEQUENCE access_seeded_id_seq OWNED BY "access_seeded"."id";
SELECT setval('access_permissions_id_seq', COALESCE((SELECT MAX("id") FROM "access_permissions"), 0) + 1, false);
SELECT setval('access_roles_id_seq', COALESCE((SELECT MAX("id") FROM "access_roles"), 0) + 1, false);
SELECT setval('access_seeded_id_seq', COALESCE((SELECT MAX("id") FROM "access_seeded"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"comments"', 'id'), COALESCE((SELECT MAX("id") FROM "comments"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"milestones"', 'id'), COALESCE((SELECT MAX("id") FROM "milestones"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"project_teams"', 'id'), COALESCE((SELECT MAX("id") FROM "project_teams"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"projects"', 'id'), COALESCE((SELECT MAX("id") FROM "projects"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"tasks"', 'id'), COALESCE((SELECT MAX("id") FROM "tasks"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"team_members"', 'id'), COALESCE((SELECT MAX("id") FROM "team_members"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"teams"', 'id'), COALESCE((SELECT MAX("id") FROM "teams"), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('"users"', 'id'), COALESCE((SELECT MAX("id") FROM "users"), 0) + 1, false);
