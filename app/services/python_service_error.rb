class PythonServiceError < StandardError
  def initialize(message = "Python service is unavailable")
    super(message)
  end
end