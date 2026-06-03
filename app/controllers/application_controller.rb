class ApplicationController < ActionController::API
  include Pagy::Method
  include Authentication

  rescue_from ActiveRecord::RecordNotFound do |error|
    render_error(error.message, "NOT_FOUND", :not_found)
  end

  private

  def render_error(message, code, status)
    render json: { error: message, code: code }, status: status
  end

  def render_validation_errors(record)
    render_error(record.errors.full_messages.to_sentence, "VALIDATION_FAILED", :unprocessable_content)
  end

  def pagination_meta(pagy)
    {
      currentPage: pagy.page,
      totalPages: pagy.pages,
      totalCount: pagy.count
    }
  end
end
