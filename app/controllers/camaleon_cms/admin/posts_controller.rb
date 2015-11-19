=begin
  Camaleon CMS is a content management system
  Copyright (C) 2015 by Owen Peredo Diaz
  Email: owenperedo@gmail.com
  This program is free software: you can redistribute it and/or modify   it under the terms of the GNU Affero General Public License as  published by the Free Software Foundation, either version 3 of the  License, or (at your option) any later version.
  This program is distributed in the hope that it will be useful,  but WITHOUT ANY WARRANTY; without even the implied warranty of  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the  GNU Affero General Public License (GPLv3) for more details.
=end
class CamaleonCms::Admin::PostsController < CamaleonCms::AdminController
  add_breadcrumb I18n.t("camaleon_cms.admin.sidebar.contents")
  before_action :set_post_type, :except => [:ajax]
  before_action :set_post, only: ['show','edit','update','destroy']
  skip_before_filter :admin_logged_actions, only: [:trash, :restore, :destroy, :ajax]
  skip_before_filter :verify_authenticity_token, only: [:ajax]

  def index
    authorize! :posts, @post_type
    posts_all = @post_type.posts
    if params[:taxonomy].present? && params[:taxonomy_id].present?
      if params[:taxonomy] == "category"
        cat_owner = current_site.full_categories.find(params[:taxonomy_id]).decorate
        posts_all = cat_owner.posts
        add_breadcrumb t("camaleon_cms.admin.post_type.category"), @post_type.the_admin_url("category")
        add_breadcrumb cat_owner.the_title, cat_owner.the_edit_url
      end

      if params[:taxonomy] == "post_tag"
        tag_owner = current_site.post_tags.find(params[:taxonomy_id]).decorate
        posts_all = tag_owner.posts
        add_breadcrumb t("camaleon_cms.admin.post_type.tags"), @post_type.the_admin_url("tag")
        add_breadcrumb tag_owner.the_title, tag_owner.the_edit_url
      end
    end

    if params[:q].present?
      posts_all = posts_all.where(params[:q].map{|text| "#{CamaleonCms::Post.table_name}.title LIKE '%#{text}%'" }.join(" OR "))
    end

    @posts = posts_all
    params[:s] = 'published' unless params[:s].present?
    @lists_tab = params[:s]
    add_breadcrumb I18n.t("camaleon_cms.admin.post_type.#{params[:s]}") if params[:s].present?
    case params[:s]
      when "published", "pending", "draft", "trash"
        @posts = @posts.where(status:  params[:s])

      when "all"
        @posts = @posts.no_trash
    end

    @btns = {published: "#{t('camaleon_cms.admin.post_type.published')} (#{posts_all.where(status: "published").size})", all: "#{t('camaleon_cms.admin.post_type.all')} (#{posts_all.no_trash.size})", pending: "#{t('camaleon_cms.admin.post_type.pending')} (#{posts_all.where(status: "pending").size})", draft: "#{t('camaleon_cms.admin.post_type.draft')} (#{posts_all.where(status: "draft").size})", trash: "#{t('camaleon_cms.admin.post_type.trash')} (#{posts_all.where(status: "trash").size})"}
    r = {posts: @posts, post_type: @post_type, btns: @btns, all_posts: posts_all, render: 'index' }
    hooks_run("list_post", r)
    @posts = r[:posts].paginate(:page => params[:page], :per_page => current_site.admin_per_page)
    render r[:render]
  end

  def show
  end

  def new
    add_breadcrumb I18n.t("camaleon_cms.admin.button.new")
    authorize! :create_post, @post_type
    @post_form_extra_settings = []
    @post ||= @post_type.posts.new
    r = {post: @post, post_type: @post_type, extra_settings: @post_form_extra_settings, render: "form"}; hooks_run("new_post", r)
    render r[:render]
  end

  def create
    authorize! :create_post, @post_type

    post_data = params[:post]
    post_data[:user_id] = cama_current_user.id
    post_data[:status] == 'pending' if post_data[:status] == 'published' && cannot?(:publish_post, @post_type)
    post_data[:data_tags] = params[:tags].to_s
    post_data[:data_categories] = params[:categories] || []

    CamaleonCms::Post.drafts.find(post_data[:draft_id]).destroy rescue nil
    @post = @post_type.posts.create(post_data)
    r = {post: @post, post_type: @post_type}; hooks_run("create_post", r)
    @post = r[:post]
    if @post.valid?
      @post.set_meta_from_form(params[:meta])
      @post.set_field_values(params[:field_options])
      @post.set_option("keywords", post_data[:keywords])
      flash[:notice] = t('camaleon_cms.admin.post.message.created', post_type: @post_type.decorate.the_title)
      r = {post: @post, post_type: @post_type}; hooks_run("created_post", r)
      redirect_to action: :edit, id: @post.id
    else
      # render 'form'
      new
    end
  end

  def edit
    add_breadcrumb I18n.t("camaleon_cms.admin.button.edit")
    authorize! :update, @post
    @post_form_extra_settings = []
    r = {post: @post, post_type: @post_type, extra_settings: @post_form_extra_settings, render: "form"}; hooks_run("edit_post", r)
    render r[:render]
  end

  def update
    @post = @post.parent if @post.draft? && @post.parent.present?
    authorize! :update, @post

    @post.drafts.destroy_all

    post_data = params[:post]
    post_data[:post_parent] = nil
    post_data[:status] == 'pending' if post_data[:status] == 'published' && cannot?(:publish_post, @post_type)
    post_data[:data_tags] = params[:tags].to_s
    post_data[:data_categories] = params[:categories] || []
    r = {post: @post, post_type: @post_type}; hooks_run("update_post", r)
    @post = r[:post]
    if @post.update(post_data)
      @post.set_meta_from_form(params[:meta])
      @post.set_field_values(params[:field_options])
      @post.set_option("keywords", post_data[:keywords])
      hooks_run("updated_post", {post: @post, post_type: @post_type})
      flash[:notice] = t('camaleon_cms.admin.post.message.updated', post_type: @post_type.decorate.the_title)
      redirect_to action: :edit, id: @post.id
    else
      # render 'form'
      edit
    end
  end

  def trash
    @post = @post_type.posts.find(params[:post_id])
    authorize! :destroy, @post
    @post.set_option('status_default', @post.status)
    @post.children.destroy_all unless @post.draft?
    @post.update_column('status', 'trash')
    @post.update_extra_data
    flash[:notice] = t('camaleon_cms.admin.post.message.trash', post_type: @post_type.decorate.the_title)
    redirect_to action: :index, s: params[:s]
  end

  def restore
    @post = @post_type.posts.find(params[:post_id])
    authorize! :update, @post
    @post.update_column('status', @post.options[:status_default] || 'pending')
    @post.update_extra_data
    flash[:notice] = t('camaleon_cms.admin.post.message.restore', post_type: @post_type.decorate.the_title)
    redirect_to action: :index, s: params[:s]
  end

  def destroy
    authorize! :destroy, @post
    r = {post: @post, post_type: @post_type, flag: true}
    hooks_run("destroy_post", r)
    if r[:flag]
      @post.destroy
      hooks_run("destroy_post", {post: @post, post_type: @post_type})
      flash[:notice] = t('camaleon_cms.admin.post.message.deleted', post_type: @post_type.decorate.the_title)
    else
      # flash[:error] = t('camaleon_cms.admin.post.message.deleted')
    end
    redirect_to action: :index, s: params[:s]
  end

  # ajax options
  def ajax
    json = {error: 'Not Found'}
    case params[:method]
      when 'exist_slug'
        slug_orig = params[:slug].to_s
        slug = slug_orig
        post_id = params[:post_id].present? ? params[:post_id] : 0
        i = 0
        while _exist_slug?(slug, post_id)  do
          i +=1
          slug = "#{slug_orig}-#{i}"
        end
        json = {slug: slug, index: i}
    end
    render json: json
  end

  private
  # define post type parent
  def set_post_type
    @post_type = current_site.post_types.find_by_id(params[:post_type_id] )
    unless @post_type.present?
      flash[:error] =  t('camaleon_cms.admin.request_error_message')
      redirect_to cama_admin_path
      return
    end
    @post_type = @post_type.decorate
    add_breadcrumb @post_type.the_title, @post_type.the_admin_url
  end

  def set_post
    begin
      @post = @post_type.posts.find(params[:id])
      @post_decorate = @post.decorate
    rescue
      flash[:error] =  t('camaleon_cms.admin.post.message.error', post_type: @post_type.decorate.the_title)
      redirect_to cama_admin_path
    end
  end

  # valid slug post
  def _exist_slug?(slug, post_id)
    current_site.posts.where("#{CamaleonCms::Post.table_name}.slug LIKE ? OR #{CamaleonCms::Post.table_name}.slug = ?",  "%-->#{slug}<!--%", slug).where("#{CamaleonCms::Post.table_name}.status != 'draft'").where(post_parent: nil).where.not(id: post_id).present?
  end
end