require 'rest-client'

module Meeco

  MeecoError = Class.new(StandardError) unless const_defined?(:MeecoError)

  module RestClientRefinements
    refine RestClient::Response do
      def json_data
        if body && body.is_a?(String) && !body.strip.empty?
          return JSON.parse body
        end
      end
    end
  end

  class Client

    VERSION = '0.0.0'

    using RestClientRefinements

    UserCredentialsNotSpecified = Class.new(MeecoError)

    attr_accessor :email, :password
    attr_accessor :token
    attr_reader :id, :user, :image_id # set when user credentials are set

    def initialize(url, email = nil, password = nil)
      @url = url
      @email = email
      @password = password
      @mutex = Mutex.new
    end

    def banksafe_story_templates
      get '/v2/story/story_templates', { by_name: 'custom' }
    end

    def connections
      get '/v2/connection/connections'
    end

    def shares(data = {})
      get '/v2/share/shares', data
    end

    def tile_items
      get '/v2/global/tile_items'
    end

    def create_connection(data)
      post '/v2/connection/connections', data
    end

    def create_story_item(data)
      post '/v2/story/story_items', data
    end

    def create_item(item_type, data)
      path = "/v2/#{item_type}/#{item_type}_items"
      post path, data
    end

    def create_share(data)
      post '/v2/share/shares', data
    end

    def create_message(data)
      post '/v2/dashboard/messages', data
    end

    def create_user(data)
      response = post '/v2/users', data, no_auth: true
      update_credentials(response)
      response
    end

    def delete_user
      delete '/v2/user'
    end

    def get_story_item(id)
      get "/v2/story/story_items/#{encode id}"
    end

    def update_story_item(id, data)
      put "/v2/story/story_items/#{encode id}", data
    end

    # upload image
    def create_image(data, options = {})
      response_data = nil
      process_binary_file(data, options) do |file|
        response = RestClient.post "#{@url}/v2/global/images", { "image[image]" => file }, { authorization: token }
        response_data = response.json_data
      end
      response_data
    end

    def create_binary(data, options = {})
      response_data = nil
      process_binary_file(data, options) do |file|
        response = RestClient.post "#{@url}/v2/global/binaries", { "binary[file]" => file, "binary[filename]" => options[:filename] }, { authorization: token }
        response_data = response.json_data
      end
      response_data
    end

    def get_user
      get '/v2/users'
    end

    def get_slot(id)
      get "/v2/global/slots/#{encode id}"
    end

    def token
      @mutex.synchronize do
        unless @token
          raise "email/password required" unless @email && @password
          # TODO: Handle expired/deleted access tokens.
          response = RestClient.post("#{@url}/v2/session/login", { grant_type: 'password', email: @email, password: @password }, { content_type: :json, accept: :json }).json_data
          update_credentials(response)
        end
      end
      @token
    end

    def image_url
      "#{@url}/v2/global/images/#{@image_id}?authentication_token=#{token}"
    end

  private

    # process binary data, save it as a file.
    # yields File object opened for reading
    # cleans up temporary file after use
    def process_binary_file(data, options = {})
      # RestClient determines mimetype from the file extension
      extension = options[:extension]
      content_type = options[:content_type]
      if extension == nil && content_type
        extension = content_type.sub(/image\//, '') if content_type.match(/image\//)
      end

      tempfile_opts = 'item_image'
      tempfile_opts = [tempfile_opts, extension] if extension
      file = Tempfile.new(tempfile_opts)
      begin
        file.write(data)
        file.close
        file.open # open for reading
        yield file
      ensure
        if file
          # remove temporary file
          file.close!
        end
      end
    end

    def update_credentials(response)
      @token = response['token_type'].capitalize + ' ' + response['access_token']
      @user = response['user'] || {}
      @id = @user['id']
      @image_id = @user['image_id']
    end

    def encode(text)
      ERB::Util.url_encode text
    end

    def get(path, parameters = {})
      RestClient.get("#{@url}#{path}", params: parameters, authorization: token, accept: :json).json_data
    end

    def post(path, data, options = {})
      opts = { content_type: :json, accept: :json }
      opts[:authorization] = token unless options[:no_auth]
      RestClient.post("#{@url}#{path}", json_body(data), opts).json_data
    end

    def put(path, data, options = {})
      opts = { content_type: :json, accept: :json }
      opts[:authorization] = token unless options[:no_auth]
      RestClient.put("#{@url}#{path}", json_body(data), opts).json_data
    end

    def delete(path, data = {}, options = {})
      opts = { content_type: :json, accept: :json }
      opts[:authorization] = token unless options[:no_auth]
      RestClient.delete("#{@url}#{path}", opts).json_data
    end

    def json_body(data)
      data && data.length ? data.to_json : nil
    end

    # A module containing solme helper methods when interacting with
    module HelperMethods

      def meeco_api_url
        'https://api-test.meeco.me'
      end

      def meeco_client_return_url(connection_id)
        'https://my-test.meeco.me/#/organisation-authorisation-succeeded?connection_id=%s' % connection_id
      end

      # This method should be overridden
      # Return an array containing [email, password] for the given user with first_name/last_name
      def user_credentials(first_name, last_name)
        raise UserCredentialsNotSpecified, "No user credentials found for `#{[first_name, last_name].compact.join(' ')}`"
      end

      # Returns a MeecoAPI::Client for the given User
      def meeco_api_client(email, password)
        Client.new(meeco_api_url, email, password)
      end

      # Returns a hash containing details from the User's me tile
      # @client MeecoAPI::Client
      def get_user_profile(client)
        items = client.tile_items
        profile_tile = items['tile_items'].find {|data| data['me'] == true }

        profile = {
            'user_id' => client.id,
          }

        # extract the users details from the me tile
        if profile
          profile_slots = items['slots'].select {|data| profile_tile['slot_ids'].include?(data['id']) }
          profile_name_value_pairs = profile_slots.collect {|data| data.values_at('name', 'value') }
          profile.merge!(Hash[profile_name_value_pairs])
        end

        profile
      end # get_user_profile

      # create a story item and then share it
      def create_and_share(client, user_id, data = {})
        attributes = tile_data_to_story_attributes(data)

        item = client.create_story_item(attributes)
        item_id = item['story_item']['id']

        # share item with user
        client.create_share 'shares' => [{ 'shareable_type' => 'TileItem', 'shareable_id' => item_id, 'user_id' => user_id }]
      end # create_and_share

      def tile_data_to_story_attributes(data = {})
        tile_data_to_tile_attributes(:story, data)
      end

      def tile_data_to_tile_attributes(item_type, data = {})
        slots_attributes = []
        nodes_attributes = []
        attachments_attributes = []
        item_name = "#{item_type}_item".to_sym
        item_attributes = data[item_name] || {}
        slots = data[:slots] || {}
        tags = data[:tags] || []

        attributes = {
          template_name: data[:template_name],
          item_name => {
            slots_attributes: slots_attributes,
            classification_nodes_attributes: nodes_attributes
          }.merge(item_attributes)
        }
        slots.each do |key, value|
          if value.kind_of?(Hash)
            # hack to support binary attachments
            if value[:binary_id]
              # set it as a binary attachment instead of a slot
              attachments_attributes << { binary_id: value[:binary_id] }
              attributes[item_name][:binary_attachments_attributes] = attachments_attributes
            else
              # hash: support specifying slots attributes explicitly.
              # convert key to 'attachment' if it's attachment_\d+
              key = "attachment" if key.to_s.match(/^attachment_\d+$/)
              slots_attributes << { name: key }.merge(value)
            end
          else
            # else simple key/value slot
            slots_attributes << {
              name: key,
              value: value,
            }
          end
        end

        tags.each do |tag|
          nodes_attributes << {
            classification_scheme_name: "tag",
            name: tag
          }
        end

        attributes
      end # tile_data_to_tile_attributes

    end # HelperMethods

  end # Client
end # MeecoAPI
