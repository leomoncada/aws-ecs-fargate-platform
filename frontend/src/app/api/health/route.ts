import { NextResponse } from 'next/server';

// Liveness only, and deliberately shallow. This is the path the ALB target
// group checks, so it must answer for this process alone. Failing it when a
// downstream is unavailable turns a partial degradation into a total outage:
// every frontend task drops out of the target group at once and the load
// balancer is left with nothing to route to.
//
// For the dependency view, see ./ready.
export async function GET() {
  return NextResponse.json({ status: 'healthy', service: 'frontend' });
}
