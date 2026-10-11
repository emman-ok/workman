import { Router } from 'express';
import { Teams, TeamMembers, ProjectTeams, Users, Projects, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { HttpError, notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';

const router = Router();

const IdParams = z.object({ id: z.coerce.number().int().positive() });
const MemberParams = z.object({
  id: z.coerce.number().int().positive(),
  userId: z.coerce.number().int().positive(),
});
const ProjectParams = z.object({
  id: z.coerce.number().int().positive(),
  projectId: z.coerce.number().int().positive(),
});
const MemberInput = z.object({ user_id: z.number().int().positive() });
const ProjectInput = z.object({ project_id: z.number().int().positive() });

const optionQuery = listQuery(['name'], { sort: 'name', order: 'asc' });

function teamIdOf(query) {
  const n = Number(query.team_id);
  return Number.isInteger(n) && n > 0 ? n : null;
}

async function loadTeam(id) {
  const team = await Teams.findByPk(id, {
    include: [
      { model: Users, as: 'createdByRef', attributes: ['id', 'name'] },
      {
        model: TeamMembers,
        as: 'teamMembers',
        include: [{ model: Users, as: 'user', attributes: ['id', 'name', 'email', 'role', 'photo', 'is_active'] }],
      },
      {
        model: ProjectTeams,
        as: 'projectTeams',
        include: [{ model: Projects, as: 'project', attributes: ['id', 'name', 'status', 'priority', 'deadline'] }],
      },
    ],
  });
  if (!team) throw notFound('Team not found.');
  const plain = team.toJSON();
  plain.teamMembers = (plain.teamMembers || []).sort((a, b) =>
    String(a.user?.name || '').localeCompare(String(b.user?.name || '')));
  plain.projectTeams = (plain.projectTeams || []).sort((a, b) =>
    String(a.project?.name || '').localeCompare(String(b.project?.name || '')));
  return plain;
}

router.get('/options/users', validate({ query: optionQuery }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = { is_active: true };
    const teamId = teamIdOf(req.query);
    if (teamId) {
      const current = await TeamMembers.findAll({ attributes: ['user_id'], where: { team_id: teamId }, raw: true });
      const ids = current.map((m) => m.user_id);
      if (ids.length) where.id = { [Op.notIn]: ids };
    }
    if (search) {
      where[Op.or] = [
        { name: { [Op.iLike]: `%${search}%` } },
        { email: { [Op.iLike]: `%${search}%` } },
      ];
    }
    const { rows, count } = await Users.findAndCountAll({
      where,
      attributes: ['id', 'name', 'email'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  }));

router.get('/options/projects', validate({ query: optionQuery }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = {};
    const teamId = teamIdOf(req.query);
    if (teamId) {
      const current = await ProjectTeams.findAll({ attributes: ['project_id'], where: { team_id: teamId }, raw: true });
      const ids = current.map((m) => m.project_id);
      if (ids.length) where.id = { [Op.notIn]: ids };
    }
    if (search) where.name = { [Op.iLike]: `%${search}%` };
    const { rows, count } = await Projects.findAndCountAll({
      where,
      attributes: ['id', 'name', 'status'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  }));

router.get('/:id', validate({ params: IdParams }),
  asyncHandler(async (req, res) => {
    res.json(await loadTeam(req.params.id));
  }));

router.post('/:id/members', validate({ params: IdParams, body: MemberInput }),
  asyncHandler(async (req, res) => {
    const teamId = req.params.id;
    const { user_id } = req.body;
    const team = await Teams.findByPk(teamId, { attributes: ['id'] });
    if (!team) throw notFound('Team not found.');
    const user = await Users.findByPk(user_id, { attributes: ['id'] });
    if (!user) throw notFound('User not found.');
    const existing = await TeamMembers.findOne({ where: { team_id: teamId, user_id } });
    if (existing) throw new HttpError(409, 'This person is already a member of the team.', { user_id: 'This person is already a member of the team.' });
    await TeamMembers.create({ team_id: teamId, user_id });
    res.status(201).json(await loadTeam(teamId));
  }));

router.delete('/:id/members/:userId', validate({ params: MemberParams }),
  asyncHandler(async (req, res) => {
    const member = await TeamMembers.findOne({ where: { team_id: req.params.id, user_id: req.params.userId } });
    if (!member) throw notFound('Member not found.');
    await member.destroy();
    res.status(204).end();
  }));

router.post('/:id/projects', validate({ params: IdParams, body: ProjectInput }),
  asyncHandler(async (req, res) => {
    const teamId = req.params.id;
    const { project_id } = req.body;
    const team = await Teams.findByPk(teamId, { attributes: ['id'] });
    if (!team) throw notFound('Team not found.');
    const project = await Projects.findByPk(project_id, { attributes: ['id'] });
    if (!project) throw notFound('Project not found.');
    const existing = await ProjectTeams.findOne({ where: { team_id: teamId, project_id } });
    if (existing) throw new HttpError(409, 'This project is already assigned to the team.', { project_id: 'This project is already assigned to the team.' });
    await ProjectTeams.create({ team_id: teamId, project_id });
    res.status(201).json(await loadTeam(teamId));
  }));

router.delete('/:id/projects/:projectId', validate({ params: ProjectParams }),
  asyncHandler(async (req, res) => {
    const link = await ProjectTeams.findOne({ where: { team_id: req.params.id, project_id: req.params.projectId } });
    if (!link) throw notFound('Project assignment not found.');
    await link.destroy();
    res.status(204).end();
  }));

export default router;
