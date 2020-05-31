package app

// These are set at build time - see makefile
var (
	Name      = "unknown"
	BuildDate = "unknown"
	Commit    = "unknown"
)

// Fields generate a fields map
func Fields() map[string]interface{} {
	return map[string]interface{}{
		"app_name":   Name,
		"build_date": BuildDate,
		"commit":     Commit,
	}
}
