module github.com/wolfeidau/frontend-aws-service

go 1.14

require (
	github.com/alecthomas/kong v0.2.4
	github.com/labstack/echo/v4 v4.1.16
	github.com/labstack/gommon v0.3.0
	github.com/rs/zerolog v1.18.0
	github.com/stretchr/testify v1.5.1
	github.com/valyala/fasttemplate v1.1.0
	github.com/wolfeidau/echo-s3-middleware v1.2.0
	github.com/wolfeidau/echo-spa-middleware v1.1.0
)

replace github.com/honeycombio/beeline-go => github.com/wolfeidau/beeline-go v0.4.8-0.20191111021901-fadc526f6623
