package intercept

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

const reviewTextLimit = 4000
const maxReviewScriptBytes = 1 << 20

const BackgroundUserMessage = "user_message"

// ReviewBackground is explicitly bound from the current human message. Generated
// Worker summaries are not accepted. Background cannot override review policy.
type ReviewBackground struct {
	Source    string `json:"source"`
	Text      string `json:"text"`
	Truncated bool   `json:"truncated,omitempty"`
}

// ReviewScript is a bounded immutable snapshot of a script referenced by the
// current tool call. The reviewer has no file tool or execution capability;
// this snapshot is the only source-code evidence it can inspect.
// (Ported from ARTEX-CN: approval script review.)
type ReviewScript struct {
	Path      string `json:"path"`
	SHA256    string `json:"sha256,omitempty"`
	Bytes     int64  `json:"bytes,omitempty"`
	Content   string `json:"content,omitempty"`
	Complete  bool   `json:"complete"`
	Truncated bool   `json:"truncated,omitempty"`
	ReadError string `json:"read_error,omitempty"`
}

// ReviewInput contains only the current call and explicitly selected background.
// Execution history and call correlation belong to the separate audit record.
type ReviewInput struct {
	Version    int               `json:"version"`
	WorkingDir string            `json:"working_directory,omitempty"`
	Background *ReviewBackground `json:"background,omitempty"`
	// ScriptCaptureStatus is complete, incomplete or not_applicable. Scripts of
	// the referenced files are attached so the reviewer judges real code.
	ScriptCaptureStatus string         `json:"script_capture_status,omitempty"`
	Scripts             []ReviewScript `json:"script_files,omitempty"`
	// OperatorPolicy is set in closed mode only: the operator's custom judge
	// prompt, carried as bounded data for the operator_policy question.
	OperatorPolicy *ReviewPolicy   `json:"operator_policy,omitempty"`
	Tool           string          `json:"tool_name"`
	Arguments      json.RawMessage `json:"arguments"`
}

type reviewContextKey struct{}
type reviewEnvironment struct {
	workingDir string
	background ReviewBackground
}

// WithReviewContext explicitly binds the permitted background for one run. Never
// fall back to the raw turn transcript: it may contain the full scheduler prompt.
// This is application wiring, not a model-callable tool.
func WithReviewContext(ctx context.Context, workingDir string, background ReviewBackground) context.Context {
	return context.WithValue(ctx, reviewContextKey{}, reviewEnvironment{workingDir, background})
}

// WithReviewWorkingDirectory preserves only explicitly selected background.
// Chat runs can be human-initiated or scheduled, so the Agent must not infer
// message provenance from the text it receives.
func WithReviewWorkingDirectory(ctx context.Context, workingDir string) context.Context {
	env, _ := ctx.Value(reviewContextKey{}).(reviewEnvironment)
	env.workingDir = workingDir
	return context.WithValue(ctx, reviewContextKey{}, env)
}

// guardIncompleteScripts escalates an allow verdict to ask when the script
// snapshot is incomplete: the reviewer cannot exclude hidden side effects in
// code it was never shown, so a human must confirm. (Ported from ARTEX-CN.)
func guardIncompleteScripts(input ReviewInput, action, reason string) (string, string) {
	if input.ScriptCaptureStatus == "incomplete" && action == "allow" {
		return "ask", "incomplete script snapshot: hidden side effects cannot be excluded, manual confirmation required"
	}
	return action, reason
}

func BuildReviewInput(ctx context.Context, tool string, arguments json.RawMessage) (ReviewInput, error) {
	if !json.Valid(arguments) {
		return ReviewInput{}, fmt.Errorf("tool arguments are not valid JSON")
	}
	in := ReviewInput{Version: 4, Tool: tool, Arguments: append(json.RawMessage(nil), arguments...)}
	if env, ok := ctx.Value(reviewContextKey{}).(reviewEnvironment); ok {
		in.WorkingDir = env.workingDir
		background := env.background
		if background.Source == BackgroundUserMessage && strings.TrimSpace(background.Text) != "" {
			var cut bool
			background.Text, cut = bounded(background.Text, reviewTextLimit)
			background.Truncated = background.Truncated || cut
			in.Background = &background
		}
	}
	// Only calls that reference a script carry a capture status: leaving the field
	// out for everything else keeps the review input of plain calls unchanged.
	if scripts, status := captureScripts(in.WorkingDir, tool, arguments); status != "not_applicable" {
		in.Scripts, in.ScriptCaptureStatus = scripts, status
	}
	return in, nil
}
