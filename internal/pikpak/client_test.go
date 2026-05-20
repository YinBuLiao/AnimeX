package pikpak

import (
	"testing"

	pikpakgo "github.com/kanghengliu/pikpak-go"
)

func TestPreferredDownloadURLPrefersBrowserCompatibleTranscode(t *testing.T) {
	file := &pikpakgo.File{
		Medias: []*pikpakgo.Media{
			{
				MediaName: "Original",
				IsOrigin:  true,
				Link:      &pikpakgo.Link{URL: "https://example.com/original-hevc.mkv"},
			},
			{
				MediaName: "1080p",
				Link:      &pikpakgo.Link{URL: "https://example.com/transcoded-h264.mp4"},
			},
		},
		WebContentLink: "https://example.com/web-content",
	}
	file.Medias[0].Video.VideoCodec = "hevc"
	file.Medias[1].Video.VideoCodec = "h264"

	got, err := preferredDownloadURL(file)
	if err != nil {
		t.Fatalf("preferredDownloadURL returned error: %v", err)
	}
	if got != "https://example.com/transcoded-h264.mp4" {
		t.Fatalf("url: got %q want browser-compatible H.264 transcode", got)
	}
}

func TestPreferredDownloadURLFallsBackToFirstMedia(t *testing.T) {
	file := &pikpakgo.File{
		Medias: []*pikpakgo.Media{
			{
				MediaName: "Original",
				Link:      &pikpakgo.Link{URL: "https://example.com/original.mkv"},
			},
		},
		WebContentLink: "https://example.com/web-content",
	}

	got, err := preferredDownloadURL(file)
	if err != nil {
		t.Fatalf("preferredDownloadURL returned error: %v", err)
	}
	if got != "https://example.com/original.mkv" {
		t.Fatalf("url: got %q want first available media URL", got)
	}
}

func TestPreferredDownloadURLFallsBackToWebContent(t *testing.T) {
	file := &pikpakgo.File{
		WebContentLink: "https://example.com/web-content",
	}

	got, err := preferredDownloadURL(file)
	if err != nil {
		t.Fatalf("preferredDownloadURL returned error: %v", err)
	}
	if got != "https://example.com/web-content" {
		t.Fatalf("url: got %q want web content link", got)
	}
}
