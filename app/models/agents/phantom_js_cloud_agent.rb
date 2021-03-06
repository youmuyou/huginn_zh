require 'json'
require 'uri'

module Agents
  class PhantomJsCloudAgent < Agent
    include ERB::Util
    include FormConfigurable
    include WebRequestConcern

    can_dry_run!

    default_schedule 'every_12h'

    description <<-MD
      此代理生成[PhantomJs Cloud](https://phantomjscloud.com/) URL，可用于呈现JavaScript密集的网页以进行内容提取.

      此代理生成的URL根据[PhantomJs Cloud API](https://phantomjscloud.com/docs/index.html)制定。 然后，可以将生成的URL提供给网站代理以获取和解析内容.
      

      [注册](https://dashboard.phantomjscloud.com/dash.html#/signup) 以获取`api`密钥，并将其添加到Huginn证书中

      有关更多信息，请参阅[Huginn Wiki] (https://github.com/huginn/huginn/wiki/Browser-Emulation-Using-PhantomJS-Cloud).

      配置说明:

      * `Api key` -  存储在Huginn中的PhantomJs Cloud API密钥凭证
      * `Url` -  要呈现的网址
      * `Mode` - 创建新的clean事件或将旧有效负载与新值合并（默认值：clean）
      * `Render type` - 渲染为没有html标签的html或纯文本（默认值：html）
      * `Output as json` - 将页面conents和元数据作为JSON对象返回（默认值：false）
      * `Ignore images` -  跳过内联图像的加载（默认值：false）
      * `Url agent` - 自定义用户代理名称（默认值：`#{default_user_agent}`） 
      * `Wait interval` - 在最后一个资源加载完成后延迟渲染的毫秒数。 如果有任何需要完成的AJAX请求或动画，这非常有用。 如果您知道没有需要等待的AJAX或动画，则可以安全地将其设置为0（默认值：1000ms）

      由于此代理仅提供最常用选项的有限子集，因此您可以按照[本指南](https://github.com/huginn/huginn/wiki/Browser-Emulation-Using-PhantomJS-Cloud)充分利用PhantomJsCloud提供的其他选项。
    MD

    event_description <<-MD
      Events look like this:
          {
            "url": "..."
          }
    MD

    def default_options
      {
        'mode' => 'clean',
        'url' => 'http://xkcd.com',
        'render_type' => 'html',
        'output_as_json' => false,
        'ignore_images' => false,
        'user_agent' => self.class.default_user_agent,
        'wait_interval' => '1000'
      }
    end

    form_configurable :mode, type: :array, values: ['clean', 'merge']
    form_configurable :api_key, roles: :completable
    form_configurable :url
    form_configurable :render_type, type: :array, values: ['html', 'plainText']
    form_configurable :output_as_json, type: :boolean
    form_configurable :ignore_images, type: :boolean
    form_configurable :user_agent, type: :text
    form_configurable :wait_interval

    def mode
      interpolated['mode'].presence || default_options['mode']
    end

    def render_type
      interpolated['render_type'].presence || default_options['render_type']
    end

    def output_as_json
      boolify(interpolated['output_as_json'].presence ||
      default_options['output_as_json'])
    end

    def ignore_images
      boolify(interpolated['ignore_images'].presence ||
      default_options['ignore_images'])
    end

    def user_agent
      interpolated['user_agent'].presence || self.class.default_user_agent
    end

    def wait_interval
      interpolated['wait_interval'].presence || default_options['wait_interval']
    end

    def page_request_settings
      prs = {}

      prs[:ignoreImages] = ignore_images if ignore_images
      prs[:userAgent] = user_agent if user_agent.present?

      if wait_interval != default_options['wait_interval']
        prs[:wait_interval] = wait_interval
      end

      prs
    end

    def build_phantom_url(interpolated)
      api_key = interpolated[:api_key]
      page_request_hash = {
        url: interpolated[:url],
        renderType: render_type
      }

      page_request_hash[:outputAsJson] = output_as_json if output_as_json

      page_request_settings_hash = page_request_settings

      if page_request_settings_hash.any?
        page_request_hash[:requestSettings] = page_request_settings_hash
      end

      request = page_request_hash.to_json
      log "Generated request: #{request}"

      encoded = url_encode(request)
      "https://phantomjscloud.com/api/browser/v2/#{api_key}/?request=#{encoded}"
    end

    def check
      phantom_url = build_phantom_url(interpolated)

      create_event payload: { 'url' => phantom_url }
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          existing_payload = interpolated['mode'].to_s == 'merge' ? event.payload : {}
          phantom_url = build_phantom_url(interpolated)

          result = { 'url' => phantom_url }
          create_event payload: existing_payload.merge(result)
        end
      end
    end

    def complete_api_key
      user.user_credentials.map { |c| { text: c.credential_name, id: "{% credential #{c.credential_name} %}" } }
    end

    def working?
      !recent_error_logs? || received_event_without_error?
    end

    def validate_options
      # Check for required fields
      errors.add(:base, 'Url is required') unless options['url'].present?
      errors.add(:base, 'API key (credential) is required') unless options['api_key'].present?
    end
  end
end
