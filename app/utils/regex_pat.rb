module RegexPat
  class << self
    def uuid(as = :string)
      s = '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
      case as
      when :string then s
      when :regex, :regex_all then /\A#{s}\z/
      when :regex_match then /#{s}/
      else raise "Unacceptable as=#{as}, class=#{as.class}"
      end
    end
  end
end
