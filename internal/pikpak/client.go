package pikpak

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"

	pikpakgo "github.com/kanghengliu/pikpak-go"
)

const KindFolder = "drive#folder"

type RemoteFile struct {
	ID             string
	Name           string
	Kind           string
	OriginalURL    string
	ParamURL       string
	ParentID       string
	Size           int64
	MimeType       string
	FileCategory   string
	FileExtension  string
	ThumbnailLink  string
	WebContentLink string
}

type RemoteTask struct {
	ID   string
	Name string
}

type API interface {
	Login() error
	FileListAll(parentID string) ([]RemoteFile, error)
	CreateFolder(name, parentID string) (RemoteFile, error)
	OfflineDownload(name, fileURL, parentID string) (RemoteTask, error)
	GetDownloadUrl(id string) (string, error)
	BatchDeleteFiles(ids []string) error
	Tokens() TokenPair
}

type Adapter struct {
	api API
}

func NewAdapter(api API) *Adapter {
	return &Adapter{api: api}
}

func (a *Adapter) Login() error {
	return a.api.Login()
}

func (a *Adapter) Tokens() TokenPair {
	return a.api.Tokens()
}

func (a *Adapter) List(parentID string) ([]RemoteFile, error) {
	return a.api.FileListAll(parentID)
}

func (a *Adapter) DownloadURL(id string) (string, error) {
	return a.api.GetDownloadUrl(id)
}

func (a *Adapter) EnsureFolder(parentID, name string) (string, error) {
	files, err := a.api.FileListAll(parentID)
	if err != nil {
		return "", fmt.Errorf("list pikpak folder: %w", err)
	}
	for _, file := range files {
		if file.Name == name && file.Kind == KindFolder {
			return file.ID, nil
		}
	}
	created, err := a.api.CreateFolder(name, parentID)
	if err != nil {
		return "", fmt.Errorf("create pikpak folder %q: %w", name, err)
	}
	return created.ID, nil
}

func (a *Adapter) HasOriginalURL(parentID, targetURL string) (bool, error) {
	files, err := a.api.FileListAll(parentID)
	if err != nil {
		return false, fmt.Errorf("list pikpak folder: %w", err)
	}
	for _, file := range files {
		if file.OriginalURL == targetURL || file.ParamURL == targetURL {
			return true, nil
		}
	}
	return false, nil
}

func (a *Adapter) HasChildren(parentID string) (bool, error) {
	files, err := a.api.FileListAll(parentID)
	if err != nil {
		return false, fmt.Errorf("list pikpak folder: %w", err)
	}
	return len(files) > 0, nil
}

func (a *Adapter) OfflineDownload(name, fileURL, parentID string) (RemoteTask, error) {
	task, err := a.api.OfflineDownload(name, fileURL, parentID)
	if err != nil {
		return RemoteTask{}, fmt.Errorf("create pikpak offline task: %w", err)
	}
	return task, nil
}

func (a *Adapter) DeleteFile(id string) error {
	id = strings.TrimSpace(id)
	if id == "" {
		return fmt.Errorf("pikpak file id is empty")
	}
	return a.api.BatchDeleteFiles([]string{id})
}

type GoAPI struct {
	client *pikpakgo.PikPakClient
}

type AuthConfig struct {
	Username     string
	Password     string
	AuthMode     string
	AccessToken  string
	RefreshToken string
	EncodedToken string
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

func NewGoAPI(username, password string) (*GoAPI, error) {
	client, err := pikpakgo.NewPikPakClient(username, password)
	if err != nil {
		return nil, err
	}
	return &GoAPI{client: client}, nil
}

func NewGoAPIWithAuth(auth AuthConfig) (*GoAPI, error) {
	client, err := pikpakgo.NewPikPakClient(auth.Username, auth.Password)
	if err != nil {
		return nil, err
	}
	accessToken := strings.TrimSpace(auth.AccessToken)
	refreshToken := strings.TrimSpace(auth.RefreshToken)
	if strings.TrimSpace(auth.EncodedToken) != "" {
		token, err := DecodeEncodedToken(auth.EncodedToken)
		if err != nil {
			return nil, err
		}
		accessToken = token.AccessToken
		refreshToken = token.RefreshToken
	}
	if accessToken != "" || refreshToken != "" {
		client.SetTokens(accessToken, refreshToken)
	}
	return &GoAPI{client: client}, nil
}

func DecodeEncodedToken(encoded string) (TokenPair, error) {
	b, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encoded))
	if err != nil {
		return TokenPair{}, fmt.Errorf("decode pikpak encoded token: %w", err)
	}
	var token TokenPair
	if err := json.Unmarshal(b, &token); err != nil {
		return TokenPair{}, fmt.Errorf("parse pikpak encoded token: %w", err)
	}
	if strings.TrimSpace(token.AccessToken) == "" || strings.TrimSpace(token.RefreshToken) == "" {
		return TokenPair{}, fmt.Errorf("pikpak encoded token must contain access_token and refresh_token")
	}
	return token, nil
}

func (g *GoAPI) Login() error {
	return g.client.Login()
}

func (g *GoAPI) Tokens() TokenPair {
	accessToken, refreshToken := g.client.Tokens()
	return TokenPair{AccessToken: accessToken, RefreshToken: refreshToken}
}

func (g *GoAPI) FileListAll(parentID string) ([]RemoteFile, error) {
	files, err := g.client.FileListAll(parentID)
	if err != nil {
		return nil, err
	}
	out := make([]RemoteFile, 0, len(files))
	for _, file := range files {
		remote := RemoteFile{
			ID:             file.ID,
			Name:           file.Name,
			Kind:           file.Kind,
			OriginalURL:    file.OriginalURL,
			ParentID:       file.ParentID,
			Size:           file.Size,
			MimeType:       file.MimeType,
			FileCategory:   file.FileCategory,
			FileExtension:  file.FileExtension,
			ThumbnailLink:  file.ThumbnailLink,
			WebContentLink: file.WebContentLink,
		}
		if file.Params != nil {
			remote.ParamURL = file.Params.URL
		}
		out = append(out, remote)
	}
	return out, nil
}

func (g *GoAPI) CreateFolder(name, parentID string) (RemoteFile, error) {
	file, err := g.client.CreateFolder(name, parentID)
	if err != nil {
		return RemoteFile{}, err
	}
	return RemoteFile{ID: file.ID, Name: file.Name, Kind: file.Kind, OriginalURL: file.OriginalURL}, nil
}

func (g *GoAPI) OfflineDownload(name, fileURL, parentID string) (RemoteTask, error) {
	task, err := g.client.OfflineDownload(name, fileURL, parentID)
	if err != nil {
		return RemoteTask{}, err
	}
	if task.Task == nil {
		return RemoteTask{}, nil
	}
	return RemoteTask{ID: task.Task.ID, Name: task.Task.Name}, nil
}

func (g *GoAPI) GetDownloadUrl(id string) (string, error) {
	file, err := g.client.GetFile(id)
	if err != nil {
		return "", err
	}
	return preferredDownloadURL(file)
}

func preferredDownloadURL(file *pikpakgo.File) (string, error) {
	if file == nil {
		return "", fmt.Errorf("pikpak file is nil")
	}
	firstMediaURL := ""
	for _, media := range file.Medias {
		if media == nil || media.Link == nil || strings.TrimSpace(media.Link.URL) == "" {
			continue
		}
		if firstMediaURL == "" {
			firstMediaURL = media.Link.URL
		}
		if browserCompatibleMedia(media) {
			return media.Link.URL, nil
		}
	}
	if firstMediaURL != "" {
		return firstMediaURL, nil
	}
	if file.WebContentLink != "" {
		return file.WebContentLink, nil
	}
	if file.Links != nil && file.Links.ApplicationOctetStream != nil {
		return file.Links.ApplicationOctetStream.URL, nil
	}
	return "", fmt.Errorf("pikpak file %s has no playable download URL", file.ID)
}

func browserCompatibleMedia(media *pikpakgo.Media) bool {
	codec := strings.ToLower(strings.TrimSpace(media.Video.VideoCodec))
	codec = strings.ReplaceAll(codec, ".", "")
	codec = strings.ReplaceAll(codec, "-", "")
	codec = strings.ReplaceAll(codec, "_", "")
	if codec == "" {
		return false
	}
	return codec == "h264" || codec == "avc" || strings.HasPrefix(codec, "avc1")
}

func (g *GoAPI) BatchDeleteFiles(ids []string) error {
	return g.client.BatchDeleteFiles(ids)
}
