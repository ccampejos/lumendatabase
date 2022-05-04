require 'validates_urls'

class Url
  include ActiveModel::Model
  include ActiveModel::Validations
  include ValidatesUrls

  attr_reader :url_original

  def [](index)
    self.instance_variable_get("@#{index}")
  end

  def []=(index, value)
    self.instance_variable_set("@#{index}", value)
  end

  def parsed
    begin
      @parsed_url ||= Addressable::URI.parse(url)
    rescue
      Addressable::URI.new
    end
  end

  def parsed_host
    # Addressable::URI#domain uses PublicSuffix under the covers,
    # so we get a tiny performance boost by preparsing and then using
    # this for both #domain and #registered_name
    begin
      PublicSuffix.parse(host, ignore_private: true)
    rescue
      PublicSuffix::Domain.new
    end
  end

  def host
    parsed.host
  end

  def domain
    parsed_host.domain
  end

  def registered_name
    parsed_host.sld
  end

  def url=(value)
    str_val = value.to_s
    @url = str_val
    @url_original = str_val if @url_original.nil?
  end

  def url_original=(value)
    @url_original = value.to_s
  end

  def url
    if @url.nil?
      @url_original
    else
      @url
    end
  end

  def as_json(*)
    {
      url: self.url
    }
  end
end
