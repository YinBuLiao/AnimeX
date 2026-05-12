package web

import (
	"context"
	"sync"
	"time"

	"bangumi-pikpak/internal/notify"
)

var (
	pushSenderOnce sync.Once
	pushSender     notify.Sender
)

func getPushSender() notify.Sender {
	pushSenderOnce.Do(func() {
		s, err := notify.NewSender()
		if err != nil {
			// Fall back to no-op rather than failing the whole server when
			// the operator misconfigures the service account.
			pushSender = notify.NoopSender{}
			return
		}
		pushSender = s
	})
	return pushSender
}

// notifyUser persists a notification into the user's center and fires an
// optional FCM push to any registered devices. Failure to push never blocks
// the persisted record — the mobile app's pull-based /api/notifications
// endpoint will surface the notification on next refresh.
func (s Server) notifyUser(username string, n Notification) {
	if username == "" {
		return
	}
	stored, err := s.notificationsStore().append(username, n)
	if err != nil {
		s.log().Warn("notify: persist failed", "user", username, "err", err)
		return
	}
	devices, err := s.deviceStore().tokensFor(username)
	if err != nil || len(devices) == 0 {
		return
	}
	sender := getPushSender()
	for _, dev := range devices {
		dev := dev
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			data := map[string]string{
				"id":   stored.ID,
				"kind": stored.Kind,
			}
			if stored.FileID != "" {
				data["file_id"] = stored.FileID
			}
			err := sender.Send(ctx, notify.Message{
				Token: dev.FcmToken,
				Title: stored.Title,
				Body:  stored.Body,
				Data:  data,
			})
			if err != nil {
				s.log().Warn("notify: FCM send failed",
					"user", username, "platform", dev.Platform, "err", err)
			}
		}()
	}
}
