package main

import (
	"context"
	"time"
)

const (
	directControlPlaneRequestBudget = 4 * time.Second
	proxiedControlPlaneWalkBudget   = 55 * time.Second
)

// controlPlaneBudget gives each direct control-plane request its own
// deadline. Remote Settings discovery is serialised before Guardian, so
// sharing one four-second context would let a slow discovery silently
// steal the user's entire Guardian authorization window.
//
// Bootstrap-proxied discovery + Guardian deliberately share one 55-second
// deadline: the Dart authorization verifier has a 60-second outer budget.
type controlPlaneBudget struct {
	parent context.Context
	shared context.Context
	cancel context.CancelFunc
}

func newControlPlaneBudget(parent context.Context, apiProxy string) *controlPlaneBudget {
	budget := &controlPlaneBudget{parent: parent}
	if apiProxy != "" {
		budget.shared, budget.cancel = context.WithTimeout(parent, proxiedControlPlaneWalkBudget)
	}
	return budget
}

// requestContext returns a fresh four-second context for Direct. In the
// proxied path it returns the same shared context; its per-call cancel is
// intentionally a no-op so discovery cannot cancel Guardian's request.
func (b *controlPlaneBudget) requestContext() (context.Context, context.CancelFunc) {
	if b.shared != nil {
		return b.shared, func() {}
	}
	return context.WithTimeout(b.parent, directControlPlaneRequestBudget)
}

func (b *controlPlaneBudget) close() {
	if b.cancel != nil {
		b.cancel()
	}
}
