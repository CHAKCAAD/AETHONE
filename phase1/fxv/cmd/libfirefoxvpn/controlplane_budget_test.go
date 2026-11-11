package main

import (
	"context"
	"testing"
	"time"
)

func TestDirectControlPlaneRequestsReceiveIndependentFourSecondBudgets(t *testing.T) {
	parent, cancel := context.WithCancel(context.Background())
	defer cancel()
	budget := newControlPlaneBudget(parent, "")
	defer budget.close()

	first, cancelFirst := budget.requestContext()
	firstDeadline, ok := first.Deadline()
	if !ok {
		t.Fatal("Direct request must have a deadline")
	}
	time.Sleep(120 * time.Millisecond)
	cancelFirst()

	second, cancelSecond := budget.requestContext()
	defer cancelSecond()
	secondDeadline, ok := second.Deadline()
	if !ok {
		t.Fatal("second Direct request must have a deadline")
	}
	if !secondDeadline.After(firstDeadline) {
		t.Fatalf("second request reused the first deadline: first=%s second=%s", firstDeadline, secondDeadline)
	}
	if remaining := time.Until(secondDeadline); remaining < 3900*time.Millisecond {
		t.Fatalf("second Direct request has only %s remaining; want a fresh four-second window", remaining)
	}
}

func TestProxiedControlPlaneRequestsShareOneFiftyFiveSecondBudget(t *testing.T) {
	parent, cancel := context.WithCancel(context.Background())
	defer cancel()
	budget := newControlPlaneBudget(parent, "socks5://127.0.0.1:1999")
	defer budget.close()

	first, cancelFirst := budget.requestContext()
	defer cancelFirst()
	second, cancelSecond := budget.requestContext()
	defer cancelSecond()
	firstDeadline, ok := first.Deadline()
	if !ok {
		t.Fatal("proxied request must have a deadline")
	}
	secondDeadline, ok := second.Deadline()
	if !ok {
		t.Fatal("second proxied request must have a deadline")
	}
	if !firstDeadline.Equal(secondDeadline) {
		t.Fatalf("proxied requests must share the bounded walk deadline: first=%s second=%s", firstDeadline, secondDeadline)
	}
	if remaining := time.Until(firstDeadline); remaining < 54*time.Second {
		t.Fatalf("new proxied walk has only %s remaining; want about 55 seconds", remaining)
	}
}
