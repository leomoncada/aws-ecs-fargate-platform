import { NextResponse } from 'next/server';

// Liveness alone is not useful here: the ALB decides whether to send user
// traffic to this task based on the response. A task that renders every page
// as a 500 because the API is unreachable must not report itself healthy.
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

  return NextResponse.json({ status: 'healthy', service: 'frontend' });
}
