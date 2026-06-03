# Serves the generated OpenAPI spec (doc/openapi.yaml) and a Redoc viewer.
# Mounted in development only (see config/routes.rb). The spec itself is
# generated from request specs via `OPENAPI=1 bundle exec rspec` (JAS-60).
class ApiDocsController < ApplicationController
  # Dev-only docs viewer; no session to authenticate against.
  skip_before_action :authenticate_session!

  VIEWER_HTML = <<~HTML.freeze
    <!DOCTYPE html>
    <html>
      <head>
        <title>Part Lifecycle Tracker API</title>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
      </head>
      <body>
        <redoc spec-url="/api-docs/openapi.yaml"></redoc>
        <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
      </body>
    </html>
  HTML

  def index
    render body: VIEWER_HTML, content_type: "text/html"
  end

  def spec
    render body: Rails.root.join("doc/openapi.yaml").read, content_type: "application/yaml"
  end
end
