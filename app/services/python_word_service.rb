require 'net/http'
require 'uri'
require 'json'

class PythonWordService
  @@http_client = nil
  
  def self.http_client
    @@http_client ||= begin
      uri = URI.parse("http://localhost:8000")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = false
      http.keep_alive_timeout = 30
      http.open_timeout = 5
      http.read_timeout = 30
      http.start
      Rails.logger.info "✅ HTTP connection pool initialized for Python service"
      http
    end
  end

  def process_sentence(sentence)
    Rails.logger.info "Processing sentence with Python: #{sentence.inspect}"
    
    http_client = self.class.http_client
    request = Net::HTTP::Post.new('/lemmatize', { 'Content-Type' => 'application/json' })
    request.body = { sentence: sentence }.to_json
    response = http_client.request(request)
    
    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      Rails.logger.info "Python API response: #{result.length} words processed"
      result
    else
      error_code = response.code.to_i
      error_message = "Python API error: #{response.code} #{response.body}"
      Rails.logger.error error_message
      
      # 500 이상의 에러는 exception으로 처리 (Ruby fallback 유도)
      if error_code >= 500
        raise PythonServiceError, "Python server error (#{error_code}): #{response.body}"
      else
        # 400번대 에러는 fallback으로 처리
        fallback_processing(sentence)
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error "Python module parsing error: #{e.message}"
    Rails.logger.error "Python output: #{response&.body}"
    raise PythonServiceError, "Python response parsing failed: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.error "Python service connection failed: #{e.class} #{e.message}"
    raise PythonServiceError, "Cannot connect to Python service: #{e.message}"
  rescue PythonServiceError
    # Re-raise PythonServiceError as-is
    raise
  rescue => e
    Rails.logger.error "Python API unexpected error: #{e.class} #{e.message}"
    raise PythonServiceError, "Unexpected Python service error: #{e.message}"
  end

  private

  def fallback_processing(sentence)
    Rails.logger.warn "Using fallback processing for sentence"
    sentence.split.map { |word| { 'word' => word, 'root' => word.downcase, 'pos' => 'NOUN' } }
  end
end