class ArticlesController < ContentController
  before_filter :verify_config
  before_filter :auto_discovery_feed, :only => [:show, :index]

  layout :theme_layout, :except => [:comment_preview, :trackback]

  cache_sweeper :blog_sweeper

  cached_pages = [:index, :read, :show, :archives, :view_page]

  if Blog.default && Blog.default.cache_option == "caches_action_with_params"
    caches_action_with_params *cached_pages
  else
    caches_page *cached_pages
  end

  helper :'admin/base'

  def index
    @articles = Article.find_all_by_date(*params.values_at(:year, :month, :day))
    @page_title = index_title
    @description = (this_blog.meta_description.empty?) ? "#{this_blog.blog_name} #{this_blog.blog_subtitle}" : this_blog.meta_description
    @keywords = (this_blog.meta_keywords.empty?) ? "" : this_blog.keywords
    
    respond_to do |format|
      format.html { render_paginated_index }
      format.atom do
        render :partial => 'articles/atom_feed', :object => @articles[0,this_blog.limit_rss_display]
      end
      format.rss do
        auto_discovery_feed(:only_path => false)
        render :partial => 'articles/rss20_feed', :object => @articles[0,this_blog.limit_rss_display]
      end
    end
  end

  def show
    @article      = this_blog.requested_article(params)
    @comment      = Comment.new
    @page_title   = @article.title
    article_meta
    
    auto_discovery_feed
    respond_to do |format|
      format.html { render :action => 'read' }
      format.atom {  render :partial => 'articles/atom_feed', :object => @article.published_feedback }
      format.rss  { render :partial => 'articles/rss20_feed', :object => @article.published_feedback }
      format.xml  { redirect_to :format => 'atom' }
    end
    rescue ActiveRecord::RecordNotFound
      error("Post not found...")
  end

  def search
    @articles = this_blog.articles_matching(params[:q])
    render_paginated_index("No articles found...")
  end

  ### Deprecated Actions ###

  def archives
    @articles = Article.find_published
    @page_title = "#{_('Archives for')} #{this_blog.blog_name}"
    @keywords = (this_blog.meta_keywords.empty?) ? "" : this_blog.keywords
    @description = "#{_('Archives for')} #{this_blog.blog_name} - #{this_blog.blog_subtitle}"
  end

  def comment_preview
    if (params[:comment][:body].blank? rescue true)
      render :nothing => true
      return
    end

    set_headers
    @comment = Comment.new(params[:comment])
    @controller = self
  end

  def author
    redirect_to authors_path, :status => 301
  end

  def category
    redirect_to categories_path, :status => 301
  end

  def tag
    redirect_to tags_path, :status => 301
  end

  def view_page
    if(@page = Page.find_by_name(params[:name].map { |c| c }.join("/"))) && @page.published?
      @page_title = @page.title
    else
      render :nothing => true, :status => 404
    end
  end

  def markup_help
    render :text => TextFilter.find(params[:id]).commenthelp
  end

  private

  def verify_config
    if User.count == 0
      redirect_to :controller => "accounts", :action => "signup"
    elsif ! this_blog.configured?
      redirect_to :controller => "admin/settings", :action => "redirect"
    else
      return true
    end
  end
  
  alias_method :rescue_action_in_public, :error

  def render_error(object = '', status = 500)
    render(:text => (object.errors.full_messages.join(", ") rescue object.to_s), :status => status)
  end

  def article_meta
    @keywords = ""
    @keywords << @article.categories.map { |c| c.name }.join(", ") << ", " unless @article.categories.empty?
    @keywords << @article.tags.map { |t| t.name }.join(", ") unless @article.tags.empty?  
    @description = @article.body.strip_html.slice(0, 200)
  end
  
  def set_headers
    headers["Content-Type"] = "text/html; charset=utf-8"
  end

  def render_paginated_index(on_empty = "No posts found...")
    return error(on_empty, :status => 200) if @articles.empty?

    @pages = Paginator.new self, @articles.size, this_blog.limit_article_display, params[:page]
    start = @pages.current.offset
    stop  = (@pages.current.next.offset - 1) rescue @articles.size
    # Why won't this work? @articles.slice!(start..stop)
    @articles = @articles.slice(start..stop)
    render :action => 'index'
  end

  def index_title
    returning('') do |page_title|
      page_title << formatted_date_selector('Archives for ')

      if params[:page]
        page_title << 'Older posts' if page_title.blank?
        page_title << ", page " << params[:page]
      end
    end
  end
  
  def formatted_date_selector(prefix = '')
    return '' unless params[:year]
    format = prefix
    format << '%A %d ' if params[:day]
    format << '%B ' if params[:month]
    format << '%Y' if params[:year]

    return(Time.mktime(*params.values_at(:year, :month, :day)).strftime(format))
  end
end
