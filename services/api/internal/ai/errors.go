package ai

import "errors"

var (
	errUnavailable = errors.New("AI_UNAVAILABLE")
	errFixture     = errors.New("FIXTURE_PRIVATE")
	errCap         = errors.New("QUOTA")
)
