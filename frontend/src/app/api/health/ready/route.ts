import { NextResponse } from 'next/server';

// Dependency check. Not wired to the ALB on purpose: it exists so a human or
// a monitor can ask "can this task actually serve a page right now?" without
// that answer being able to pull the task out of rotation.
export async function GET() {
  const apiUrl = process.env.NEXT_PUBLIC_API_URL;

  try {
    const res = await fetch(`${apiUrl}/health`, {
      cache: 'no-store',
      signal: AbortSignal.timeout(2000),
    });
    if (!res.ok) {
      return NextResponse.json(
        { status: 'unhealthy', service: 'frontend', dependency: 'backend', detail: `status ${res.status}` },
        { status: 503 },
      );
    }
  } catch (err) {
    return NextResponse.json(
      {
        status: 'unhealthy',
        service: 'frontend',
        dependency: 'backend',
        detail: err instanceof Error ? err.message : 'unreachable',
      },
      { status: 503 },
    );
  }

  return NextResponse.json({ status: 'ready', service: 'frontend', dependency: 'backend' });
}
