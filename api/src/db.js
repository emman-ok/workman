// The Sequelize connection (PostgreSQL). Owned by AppWand.
import 'dotenv/config';
import pg from 'pg';
import { Sequelize } from 'sequelize';

// COUNT(*) and BIGINT ids come back as strings otherwise.
pg.types.setTypeParser(20, (value) => (value === null ? null : Number(value)));

const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD || undefined, {
  dialect: 'postgres',
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  logging: process.env.DB_LOG === 'true' ? console.log : false,
  pool: { max: 10 },
  define: { timestamps: false, freezeTableName: true },
});

export default sequelize;
