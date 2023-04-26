require "logger"

module Medup
  class Tool
    ASSETS_DIR_NAME          = "assets"
    SOURCE_AUTHOR_POSTS      = "overview"
    SOURCE_RECOMMENDED_POSTS = "has-recommended"
    MARKDOWN_FORMAT          = "md"
    JSON_FORMAT              = "json"

    ctx : ::Medup::Context
    update : Bool
    user : String?
    publication : String?
    articles : Array(String)
    logger : Logger

    def initialize(
      @ctx : ::Medup::Context = ::Medup::Context.new,
      format : String? = MARKDOWN_FORMAT,
      source : String? = SOURCE_AUTHOR_POSTS,
      @user : String? = nil,
      @publication : String? = nil,
      @articles : Array(String) = Array(String).new
    )
      @logger = @ctx.logger
      @client = ::Medup::Client.new(@ctx, @user, @publication)

      @dist = @ctx.settings.posts_dist
      @assets_dist = @ctx.settings.assets_dist

      @source = (source || SOURCE_AUTHOR_POSTS).as(String)
      @format = (format || MARKDOWN_FORMAT).as(String)
      @update = @ctx.settings.update_content?
    end

    def backup
      posts = Array(String).new
      user = @user
      publication = @publication
      puts "Starting backup for #{publication}"
      posts = if @ctx.platform_medium?
                client = @client.adapter.as(Medium::Client)
                Medium::Client.default = client
                if !@articles.empty?
                  client.normalize_urls(@articles)
                elsif !@user.nil?
                  client.streams(@source)
                elsif !@publication.nil?
                  client.collection_archive
                end
              else
                if !@articles.empty?
                  @articles
                elsif !user.nil?
                  @client.post_urls_by_author(user)
                elsif !publication.nil?
                  @client.post_urls_by_author(publication)
                end
              end

      raise "No articles to backup" if posts.nil? || posts.empty?

      create_directory(@dist)
      create_directory(@assets_dist)
      process_posts_async(posts)
    end

    def process_posts_async(posts)
      puts "Posts count: #{posts.size}"

      channel_start = Channel(String).new(2)
      channel_finished = Channel(String).new(2)

      posts.each do |post_url|
        spawn do
          channel_start.send(post_url)
          process_post(post_url)
          channel_finished.send(post_url)
        end
      end

      posts.size.times do
        channel_start.receive?
        channel_finished.receive?
      end

      channel_start.close
      channel_finished.close
    end

    def close : Nil
      @client.close unless @client.nil?
    end

    def process_post(post_url : String)
      client = ::Medup::Client.new(@ctx, @user, @publication)
      post = client.post_by_url(post_url)

      save(post, @format)
    rescue ex : ::Medium::Error | ::Medium::InvalidContentError
      @logger.error "error: could not process #{post_url}: #{ex.message}"
    rescue ex : Exception
      @logger.error "error: #{ex.inspect}"
      @logger.error ex.inspect_with_backtrace
    end

    def save(post, format = "json")
      slug = post.slug
      created_at = post.created_at

      filename = [created_at.to_s("%F"), slug].reject(&.empty?).join("-") + "." + format
      filepath = File.join(@dist, filename)

      if File.exists?(filepath)
        return unless @update
        if !@ctx.settings.dry_run?
          File.delete(filepath + ".old") if File.exists?(filepath + ".old")
          File.rename(filepath, filepath + ".old")
        end
      end
      puts "Create file #{filepath}"

      if format == "json"
        if !@ctx.settings.dry_run?
          File.write(filepath, post.to_pretty_json)
        end
        return
      end

      content, assets = post.to_md
      if !@ctx.settings.dry_run?
        File.write(filepath, content)
      end

      if @ctx.settings.assets_image?
        assets.each do |filename, content|
          filepath = File.join(@assets_dist, filename)
          @logger.debug "Create asset #{filepath}"
          if !@ctx.settings.dry_run?
            File.write(filepath, content)
          end
        end
      end
    end

    def create_directory(path)
      unless File.directory?(path)
        @logger.debug "Create directory #{path}"
        Dir.mkdir_p(path) if !@ctx.settings.dry_run?
      end
    end
  end
end
