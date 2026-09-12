import { describe, it, expect, vi, afterEach } from 'vitest';
import { GET } from './route';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('frontend liveness route', () => {
  it('reports healthy', async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ status: 'healthy' });
  });

  // The ALB routes on this endpoint. A backend outage must not evict every
  // frontend task from the target group.
  it('stays healthy even when the backend is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));
    const res = await GET();
    expect(res.status).toBe(200);
  });
});
