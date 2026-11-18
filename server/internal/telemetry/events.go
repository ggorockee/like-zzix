package telemetry

// AllowedEvents is the allowlist for POST /v1/events. It must match the app's
// AppEvent enum (mobile/lib/services/telemetry_service.dart). Unknown names are
// rejected rather than recorded, which keeps label cardinality fixed.
var AllowedEvents = map[string]bool{
	"app_open":            true, // 앱 실행 (스플래시 통과)
	"preset_selected":     true, // 프리셋 선택
	"perfect_match":       true, // "지금 찍으세요!" 진입
	"photo_saved":         true, // 촬영 후 갤러리 저장 성공
	"photo_save_failed":   true, // 저장 실패 (권한 거부 포함)
	"camera_unavailable":  true, // 카메라 열기 실패/권한 거부
	"gallery_opened":      true, // 갤러리 버튼/스낵바 "보기"
	"update_prompt_shown": true, // 선택 업데이트 팝업 노출
	"force_update_shown":  true, // 강제 업데이트 팝업 노출
	"update_accepted":     true, // 업데이트 버튼 → 스토어 이동
	"update_dismissed":    true, // 선택 업데이트 "나중에"
}

// PresetEvents may carry a "preset" field and are also counted per preset.
var PresetEvents = map[string]bool{
	"preset_selected": true,
	"perfect_match":   true,
	"photo_saved":     true,
}

const (
	// MaxEventsPerBatch bounds one request; the app sends one entry per (event, preset).
	MaxEventsPerBatch = 40
	// MaxEventCount bounds a single entry's count so a bad client cannot skew totals.
	MaxEventCount = 500
)
