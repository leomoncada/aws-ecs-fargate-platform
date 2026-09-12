import { describe, it, expect, vi, afterEach } from 'vitest';
import { GET } from './route';

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe('frontend readiness route', () => {
  it('reports ready when the backend answers', async () => {
    vi.stubEnv('NEXT_PUBLIC_API_URL', 'http://backend:8000');
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 200 })));

    const res = await GET();

    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ status: 'ready' });
  });

  // The ALB routes user traffic based on this endpoint. If it returns 200
  // while the backend is unreachable, every page render 500s behind a
  // target group that reports itself perfectly healthy.
  it('reports unhealthy when the backend cannot be reached', async () => {
    vi.stubEnv('NEXT_PUBLIC_API_URL', 'http://backend:8000');
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('ECONNREFUSED')));

    const res = await GET();

    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({ status: 'unhealthy' });
  });

  it('reports unhealthy when the backend returns an error status', async () => {
    vi.stubEnv('NEXT_PUBLIC_API_URL', 'http://backend:8000');
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 500 })));

    const res = await GET();

    expect(res.status).toBe(503);
  });
});
