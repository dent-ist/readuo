'use strict';

const { createHash } = require('node:crypto');

function notificationId(sourcePath, createdAt) {
  if (!sourcePath || !createdAt || !Number.isInteger(createdAt.seconds)) {
    throw new Error('A notification needs an immutable source generation.');
  }
  return createHash('sha256').update(`${sourcePath}:${createdAt.seconds}:${createdAt.nanoseconds}`).digest('hex');
}

function enabled(preferences, type) {
  return ['friendRequest', 'requestAccepted', 'like', 'comment', 'booksAdded'].includes(type)
    && preferences[type] !== false;
}

function sameGeneration(left, right) {
  return !!left && !!right && left.seconds === right.seconds && left.nanoseconds === right.nanoseconds;
}

function acceptanceActors(members) {
  if (!Array.isArray(members) || members.length !== 2 || members.some(member => typeof member !== 'string' || !member || member.includes('/')) || members[0] === members[1]) {
    throw new Error('Invalid friendship members.');
  }
  return { recipientId: members[0], actorId: members[1] };
}

module.exports = { notificationId, enabled, sameGeneration, acceptanceActors };
