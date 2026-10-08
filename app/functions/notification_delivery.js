'use strict';

const { createHash, randomUUID } = require('node:crypto');
const { enabled } = require('./notification_policy');

const lifetime = 60 * 60 * 1000;
const leaseDuration = 180000;
const tokenLifetime = 30 * 24 * lifetime;
const terminal = new Set(['sent', 'skipped', 'expired', 'failed']);
const invalidTokens = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);
const permanentErrors = new Set(['messaging/invalid-argument', 'messaging/mismatched-credential', 'messaging/invalid-package-name']);
const milliseconds = value => value?.toMillis?.() ?? (value?.seconds == null ? 0 : value.seconds * 1000);
const tokenKey = token => createHash('sha256').update(token).digest('hex');

async function deliverPush({ database, messaging, reference, userId, notificationId, sourceAvailable, tokenAllowed = () => true, notificationPayload = () => ({ title: 'Readuo', body: 'You have a new notification. Open Readuo to view it.' }), now = Date.now, random = Math.random }) {
  const lease = randomUUID();
  const preferencesRef = database.doc(`users/${userId}/preferences/notifications`);
  const claimed = await database.runTransaction(async transaction => {
    const [current, preferences] = await transaction.getAll(reference, preferencesRef);
    if (!current.exists || terminal.has(current.data().pushState)) return null;
    const notice = current.data();
    const age = now() - milliseconds(notice.createdAt);
    if (age < -300000 || age > lifetime || (notice.pushState === 'claimed' && !notice.pushLeaseUntil)) {
      transaction.update(reference, { pushState: 'expired' });
      return null;
    }
    if ((notice.pushLeaseUntil || 0) > now() || (notice.pushNextAt || 0) > now()) throw new Error('Notification delivery is deferred.');
    if ((notice.pushAttempts || 0) >= 6) {
      transaction.update(reference, { pushState: 'failed' });
      return null;
    }
    const allowed = notice.recipientId === userId && enabled(preferences.data() || {}, notice.type) && await sourceAvailable(transaction, database, notice);
    if (!allowed) {
      transaction.update(reference, { pushState: 'skipped' });
      return null;
    }
    transaction.update(reference, { pushState: 'claimed', pushLease: lease, pushLeaseUntil: now() + leaseDuration, pushAttempts: (notice.pushAttempts || 0) + 1 });
    return { ...notice, pushAttempts: (notice.pushAttempts || 0) + 1 };
  });
  if (!claimed) return;
  let retry = false;
  let revoked = false;
  const outcomes = { ...(claimed.pushResults || {}) };
  try {
    const tokens = await database.collection(`users/${userId}/notificationTokens`).get();
    const uniqueTokens = new Set();
    const candidates = [...tokens.docs].sort((left, right) => milliseconds(right.data().updatedAt) - milliseconds(left.data().updatedAt)).filter(snapshot => {
      const token = snapshot.data().token;
      if (typeof token !== 'string' || token.length === 0 || !tokenAllowed(snapshot.data()) || outcomes[tokenKey(token)] || uniqueTokens.has(token)) return false;
      uniqueTokens.add(token);
      return true;
    });
    for (let offset = 0; offset < candidates.length; offset += 500) {
      const chunk = candidates.slice(offset, offset + 500);
      const active = await database.runTransaction(async transaction => {
        const [current, preferences, ...latest] = await transaction.getAll(reference, preferencesRef, ...chunk.map(snapshot => snapshot.ref));
        if (!current.exists || current.data().pushLease !== lease) return null;
        const allowed = now() - milliseconds(claimed.createdAt) <= lifetime && enabled(preferences.data() || {}, claimed.type) && await sourceAvailable(transaction, database, claimed);
        if (!allowed) return null;
        return latest.filter((snapshot, index) => {
          if (!snapshot.exists || snapshot.data().token !== chunk[index].data().token || !tokenAllowed(snapshot.data())) return false;
          if (now() - milliseconds(snapshot.data().updatedAt) > tokenLifetime) {
            transaction.delete(snapshot.ref);
            return false;
          }
          return true;
        });
      });
      if (active == null) { revoked = true; break; }
      if (active.length === 0) continue;
      const response = await messaging.sendEachForMulticast({
        tokens: active.map(snapshot => snapshot.data().token),
        notification: notificationPayload(),
        data: { notificationId, recipientId: userId },
        android: { priority: 'normal', collapseKey: notificationId, ttl: Math.max(0, Math.min(lifetime, lifetime - (now() - milliseconds(claimed.createdAt)))), notification: { tag: notificationId, channelId: 'readuo_social' } },
      });
      await database.runTransaction(async transaction => {
        const [current, ...latest] = await transaction.getAll(reference, ...active.map(snapshot => snapshot.ref));
        if (!current.exists || current.data().pushLease !== lease) throw new Error('Notification lease changed.');
        response.responses.forEach((result, index) => {
          const token = active[index].data().token;
          const code = result.error?.code;
          if (result.success) outcomes[tokenKey(token)] = 'sent';
          else if (invalidTokens.has(code)) {
            outcomes[tokenKey(token)] = 'invalid';
            if (latest[index].exists && latest[index].data().token === token) transaction.delete(latest[index].ref);
          } else if (permanentErrors.has(code)) outcomes[tokenKey(token)] = 'failed';
          else retry = true;
        });
        transaction.update(reference, { pushResults: outcomes });
      });
    }
  } catch (_) {
    retry = true;
  }
  await database.runTransaction(async transaction => {
    const current = await transaction.get(reference);
    if (!current.exists || current.data().pushLease !== lease) return;
    const exhausted = claimed.pushAttempts >= 6 || now() - milliseconds(claimed.createdAt) > lifetime;
    transaction.update(reference, {
      pushState: revoked ? 'skipped' : retry && !exhausted ? 'pending' : retry || !Object.values(outcomes).includes('sent') ? 'failed' : 'sent',
      pushLeaseUntil: 0,
      pushNextAt: retry ? now() + Math.min(900000, 60000 * 2 ** (claimed.pushAttempts - 1)) + Math.floor(random() * 10000) : 0,
    });
    if (exhausted) retry = false;
  });
  if (retry && !revoked) throw new Error('Notification delivery will retry.');
}

module.exports = { deliverPush, tokenKey };
