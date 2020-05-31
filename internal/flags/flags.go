package flags

import "github.com/alecthomas/kong"

// Config all the configuration for the service
type Config struct {
	Version    kong.VersionFlag
	Debug      bool   `help:"Enable debug logging." env:"DEBUG"`
	Pretty     bool   `help:"Enable logging with colors." env:"PRETTY"`
	Tracing    bool   `help:"Enable tracing using honeycomb." env:"TRACING"`
	Stage      string `help:"The stage this is deployed." env:"STAGE"`
	Branch     string `help:"The branch this is deployed." env:"BRANCH"`
	AppName    string `help:"The application name under which this service is deployed." env:"APP_NAME"`
	DomainName string `help:"The domain which is served." env:"DOMAIN_NAME"`
	S3Bucket   string `help:"The s3 bucket used to serve files." env:"S3_BUCKET"`
	Address    string `help:"The bind address." env:"ADDR" default:":8000"`
}
