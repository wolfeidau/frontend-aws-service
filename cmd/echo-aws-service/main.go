package main

import (
	"context"
	"io/ioutil"

	"github.com/alecthomas/kong"
	"github.com/labstack/echo/v4"
	echomiddleware "github.com/labstack/echo/v4/middleware"
	echolog "github.com/labstack/gommon/log"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	s3middleware "github.com/wolfeidau/echo-s3-middleware"
	spa "github.com/wolfeidau/echo-spa-middleware"
)

var (
	version = "unknown"
	cli     struct {
		Debug      bool   `help:"Enable debug logging." env:"DEBUG"`
		DomainName string `help:"The domain which is served." env:"DOMAIN_NAME"`
		S3Bucket   string `help:"The s3 bucket used to serve files." env:"S3_BUCKET"`
		Address    string `help:"The bind address." env:"ADDR" default:":8000"`
	}
)

func main() {
	kong.Parse(&cli)

	log.Info().Str("version", version).Msg("starting frontendproxy")

	e := echo.New()

	if cli.Debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	} else {
		zerolog.SetGlobalLevel(zerolog.WarnLevel)
	}

	// shut down all the default output of echo
	e.Logger.SetOutput(ioutil.Discard)
	e.Logger.SetLevel(echolog.OFF)

	e.Use(echomiddleware.RequestID())
	// e.Use(echomiddleware.Logger())

	e.Pre(echomiddleware.AddTrailingSlash()) // required to ensure trailing slash is appended
	e.Use(spa.IndexWithConfig(spa.IndexConfig{
		DomainName:    cli.DomainName,
		SubDomainMode: true,
	}))

	fs := s3middleware.New(s3middleware.FilesConfig{
		Summary: func(ctx context.Context, data map[string]interface{}) {
			log.Info().Fields(data).Msg("processed s3 request")
		},
		OnErr: func(ctx context.Context, err error) {
			log.Error().Err(err).Stack().Msg("failed to process s3 request")
		},
	})

	e.GET("/healthz", func(c echo.Context) error {
		return c.JSON(200, map[string]string{"msg": "ok", "version": version})
	})

	// serve static files from the supplied bucket
	e.Use(fs.StaticBucket(cli.S3Bucket))

	log.Info().Str("addr", cli.Address).Msg("starting listener")
	log.Fatal().Err(e.Start(cli.Address)).Msg("failed to start echo listener")
}
