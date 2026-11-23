package api

import "net/http"

func (s *Server) aiStatus(w http.ResponseWriter, r *http.Request) {
	_, logged := s.currentUser(r)
	if s.AI == nil {
		writeJSON(w, 200, map[string]any{"provider": "xai", "configured": false, "showButton": false, "reason": "no_key", "guestDaily": 3, "memberDaily": 30, "fixture": true}, true)
		return
	}
	writeJSON(w, 200, s.AI.Status(logged), true)
}

func (s *Server) aiUnderstand(w http.ResponseWriter, r *http.Request) {
	if s.AI == nil {
		writeErr(w, http.StatusServiceUnavailable, "AI_UNAVAILABLE", "aiUnavailable", nil)
		return
	}
	var body struct {
		Sentence string `json:"sentence"`
	}
	if err := decodeLoose(r, &body); err != nil || body.Sentence == "" {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	user, logged := s.currentUser(r)
	subject := ""
	if logged {
		subject = "user:" + user
	} else {
		voucher := r.Header.Get("X-MH-AI-Voucher")
		if voucher == "" {
			writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
			return
		}
		subject = "guest:" + voucher
	}
	out, reason, err := s.AI.Understand(r.Context(), body.Sentence, subject, logged)
	switch reason {
	case "no_key":
		writeErr(w, http.StatusServiceUnavailable, "AI_UNAVAILABLE", "aiUnavailable", nil)
		return
	case "fixture":
		writeErr(w, http.StatusForbidden, "FIXTURE_PRIVATE", "fixturePrivate", nil)
		return
	case "daily_cap", "monthly_cap":
		writeErr(w, http.StatusTooManyRequests, "QUOTA", reason, nil)
		return
	case "provider":
		writeErr(w, http.StatusBadGateway, "AI_PROVIDER", "aiProvider", nil)
		return
	}
	if err != nil {
		writeErr(w, http.StatusServiceUnavailable, "AI_UNAVAILABLE", "aiUnavailable", nil)
		return
	}
	writeJSON(w, 200, out, true)
}
