'use strict';

class ModerationError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function requireUser(request) {
  if (!request.auth?.uid) throw new ModerationError('unauthenticated', 'Sign in to continue.');
  return request.auth.uid;
}

function requireModerator(request) {
  const uid = requireUser(request);
  if (request.auth.token?.moderator !== true) {
    throw new ModerationError('permission-denied', 'Moderator access required.');
  }
  return uid;
}

function object(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !keys.includes(key))) {
    throw new ModerationError('invalid-argument', 'Invalid request fields.');
  }
  return value;
}

function bounded(value, maximum, allowEmpty = false) {
  if (typeof value !== 'string' || value.length > maximum || (!allowEmpty && !value.trim())) {
    throw new ModerationError('invalid-argument', 'Invalid text length.');
  }
  return value;
}

function identifier(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,256}$/.test(value)) {
    throw new ModerationError('invalid-argument', 'Invalid identifier.');
  }
  return value;
}

function targetPath(target) {
  object(target, ['kind', 'id', 'parentKind', 'parentId']);
  if (target.kind === 'support') {
    if (Object.keys(target).length !== 1) throw new ModerationError('invalid-argument', 'Support has no reader target.');
    return null;
  }
  const collections = { post: 'circlePosts', review: 'circleReviews', profile: 'readerProfiles' };
  if (target.kind === 'comment') {
    if (!['post', 'review'].includes(target.parentKind)) throw new ModerationError('invalid-argument', 'Invalid comment parent.');
    return `${collections[target.parentKind]}/${identifier(target.parentId)}/comments/${identifier(target.id)}`;
  }
  if (!collections[target.kind] || target.parentKind !== undefined || target.parentId !== undefined) {
    throw new ModerationError('invalid-argument', 'Invalid target.');
  }
  return `${collections[target.kind]}/${identifier(target.id)}`;
}

const reasons = ['Harassment or bullying', 'Inappropriate content', 'Spam or misleading content', 'Privacy concern', 'Something else'];

const filterVersion = 'basic-threats-v1';
const prohibitedPattern = '(?:^|[^a-z0-9_])(?:i[ \\t\\r\\n]+will[ \\t\\r\\n]+kill[ \\t\\r\\n]+you|kill[ \\t\\r\\n]+yourself)(?:$|[^a-z0-9_])';
const filterExplanation = 'Remove direct threats of violence or encouragement to self-harm before sharing.';

function filterContent(text) {
  bounded(text, 5000, true);
  const prohibited = new RegExp(prohibitedPattern).test(text.toLowerCase());
  return {
    allowed: !prohibited,
    policyVersion: filterVersion,
    violations: prohibited ? [{ id: 'direct-threat-or-self-harm', explanation: filterExplanation }] : [],
  };
}

function enforceContent(text, policy) {
  const result = filterContent(text, policy);
  if (!result.allowed) {
    throw new ModerationError('failed-precondition', 'Revise your draft before sharing.', { kind: 'content-filtered', ...result });
  }
  return result;
}

module.exports = { ModerationError, requireUser, requireModerator, object, bounded, identifier, targetPath, reasons, filterContent, enforceContent, prohibitedPattern, filterVersion };
