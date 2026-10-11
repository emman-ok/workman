import { Router } from 'express';
import { Teams, TeamMembers, ProjectTeams, Projects, sequelize, Op, fn, col } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';

const router = Router();

router.get(
  '/',
  validate({ query: listQuery(['name', 'created_at', 'id'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = search ? { name: { [Op.iLike]: `%${search}%` } } : {};
    const { rows, count } = await Teams.findAndCountAll({
      where,
      order: [[sort, order.toUpperCase()], ['id', 'ASC']],
      limit,
      offset: (page - 1) * limit,
    });

    const ids = rows.map((t) => t.id);
    const memberCounts = {};
    const projectsByTeam = {};

    if (ids.length > 0) {
      const counts = await TeamMembers.findAll({
        attributes: ['team_id', [fn('COUNT', col('id')), 'count']],
        where: { team_id: { [Op.in]: ids } },
        group: ['team_id'],
        raw: true,
      });
      for (const c of counts) memberCounts[c.team_id] = Number(c.count) || 0;

      const links = await ProjectTeams.findAll({
        where: { team_id: { [Op.in]: ids } },
        include: [{ model: Projects, as: 'project', attributes: ['id', 'name'] }],
        order: [['id', 'ASC']],
      });
      for (const link of links) {
        if (!link.project) continue;
        if (!projectsByTeam[link.team_id]) projectsByTeam[link.team_id] = [];
        projectsByTeam[link.team_id].push({ id: link.project.id, name: link.project.name });
      }
    }

    const items = rows.map((t) => {
      const projects = projectsByTeam[t.id] || [];
      return {
        ...t.toJSON(),
        member_count: memberCounts[t.id] || 0,
        project_count: projects.length,
        projects,
      };
    });

    res.json({ items, total: count });
  })
);

router.delete(
  '/:id',
  validate({ params: { id: z_id() } }),
  asyncHandler(async (req, res) => {
    const team = await Teams.findByPk(req.params.id);
    if (!team) throw notFound('Team not found.');
    await sequelize.transaction(async (transaction) => {
      await TeamMembers.destroy({ where: { team_id: team.id }, transaction });
      await ProjectTeams.destroy({ where: { team_id: team.id }, transaction });
      await team.destroy({ transaction });
    });
    res.status(204).end();
  })
);

function z_id() {
  return z.coerce.number().int().positive();
}

export default router;
