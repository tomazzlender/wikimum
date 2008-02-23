class Page < ActiveRecord::Base

  belongs_to :updater, :class_name => 'User', :foreign_key => 'updated_by'
  belongs_to :creator, :class_name => 'User', :foreign_key => 'created_by'
  has_many   :revisions, :dependent => :destroy
  has_many   :permissions, :dependent => :destroy

  after_validation :verify_updater
  before_save   :compile, :fix_title
  before_update :bump_revision
  before_create :set_default_permission
  after_save    :revised_unset

  attr_accessor :revised

  def initialize(attributes = nil)
    super
    @revised = false
  end

  def self.find_by_title(title = nil, user = nil)
    return false if title.nil?

    shorthand = title.space_to_underline

    Page.find(:first, 
              :conditions => [ "shorthand_title = ? AND #{read_conditions_for(user)}", shorthand ],
              :include    => [ :permissions, :updater ])
  end

  def self.find_all_by_section(section = nil, user = nil)
    if section
      Page.find(:all, 
                :conditions => [
                  "title_char = ? AND #{read_conditions_for(user)}", section ], 
                :include    => :permissions,
                :order      => 'title_char, title ASC')
    else
      Page.find(:all, 
                :conditions => read_conditions_for(user),
                :include    => :permissions,
                :order      => 'title_char, title ASC')
    end
  end

  def self.find_all_with_read_permission_for(user)
    Page.find(:all,
              :conditions => read_conditions_for(user),
              :include    => :permissions,
              :order      => 'title ASC')
  end

  def self.find_all_by_date(year = nil, month = nil, day = nil, user = nil)
    from, to = Page.time_delta(year, month, day)

    Page.find(:all,
              :conditions => [
                "(updated_on BETWEEN ? AND ?) AND #{read_conditions_for(user)}",
                from, to],
              :include    => [ :permissions, :updater ],
              :order      => 'updated_on DESC')
  end

  # From Typo
  def self.search(keyword, user = nil)
    if not keyword.to_s.strip.empty?
      keyword = keyword.gsub('*', '%')
      tokens = keyword.split.collect { |c| "%#{c.downcase}%" }
      condition = [ (["(LOWER(content) LIKE ? OR LOWER(description) LIKE ? OR LOWER(title) LIKE ?)"] * tokens.size).join(" AND ") + 
        "AND #{read_conditions_for(user)}",
        *tokens.collect { |token| [token] * 3 }.flatten ]

      Page.find(:all,
                :conditions => condition,
                :include    => :permissions)
    else
      []
    end
  end

  def update_date
    self.updated_on.without_hours
  end

  def section
    self.title_char
  end

  def compile
    self.compiled_content     = Markup.to_html(self.content, self.markup)
    self.compiled_comment     = self.comment
    self.compiled_description = self.description
  end

  def fix_title
    self.title           = self.title.strip
    self.title_char      = self.title.first_char.capitalize
    self.shorthand_title = self.title.space_to_underline
    
    true
  end

  def set_default_permission
    self.permissions << OwnPermission.new(:user => self.creator)
    self.permissions << ReadPermission.new(:global => true)
  end

  def changed?
    page = Page.find(self.id)

    %w( title content description ).each do |name|
      if page.attributes[name] != self.attributes[name]
        return true
      end
    end

    return page.markup != self.markup
  end


  # Has to be run manually to avoid loops
  def revise
    raise if self.changed? or @revised

    ActiveRecord::Base.record_timestamps = false

    revision            = Revision.new
    revision.attributes = self.attributes
    revision.page_id    = self.id
    revision.save!
    @revised = true

    ActiveRecord::Base.record_timestamps = true
  end

  def revoke_latest_revision
    page_revisions = self.revisions(:refresh).sort {|x,y| x.revision <=> y.revision }
    page_revisions.last.destroy
  end


  # Alias
  def number
    revision
  end

  def previous
    revision <= 1 ? 1 : revision - 1
  end

  def first?
    revision == 1
  end

  def to_param
    self.shorthand_title
  end

  def to_s
    self.title
  end

  def has_permissions?
    not self.permissions.empty?
  end

  def has_global_permission?
    self.permissions.each do |permission|
      return true if permission.global?
    end

    false
  end

  def read_by?(user)
    return true if user.admin?
    self.permissions.each do |permission|
      return true if permission.read_by?(user)
    end

    false
  end

  def write_by?(user)
    return true if user.admin?
    self.permissions.each do |permission|
      return true if permission.write_by?(user)
    end

    false
  end

  def own_by?(user)
    return true if user.admin?
    self.permissions.each do |permission|
      return true if permission.own_by?(user)
    end

    false
  end

  protected

  def revised_unset
    @revised = false
  end
  
  # Make sure the user is handled correctly, guests should get extra
  # attention
  def verify_updater
    if self.updater.guest?
      self.updater.save_with_validation(false) # for now, we should change the validations
    else
      true
    end
  end

  def bump_revision
    self.revision += 1
  end

  def self.read_conditions_for(user)
    condition = ''
    if user and user.admin?
      condition << 'true'
    else
      if not user.nil? and not user.id.nil?
        condition << "(permissions.user_id = '#{user.id}' " 
        condition << "OR permissions.global = '1' "
        if not user.groups.empty?
          user.groups.each do |group|
            condition << "OR permissions.group_id = '#{group.id}'"
          end
        end
        condition << ')'
      else
        condition << "permissions.global = '1'"
      end
    end
    condition
  end

  # Credit to Typo for the idea
  def self.time_delta(year, month, day)
    from = Time.mktime(year || 1970, month || 1, day || 1)

    to = from + 1.year  unless year.blank?
    to = from + 1.month unless month.blank?
    to = from + 1.day   unless day.blank?
    to = Time.now       unless year

    return [from, to]
  end

	validates_format_of     :title, :with   => /^[\d\w\sÅÄÖåäö_:-]*$/, 
		:on => :create, :message => 'Titeln får endast innehålla A-Ö, 0-9, _, - och :'
	validates_length_of     :title, :within => 1..35, :too_short => 'Minst ett tecken i titeln', 
		:too_long => 'Inte längre än 35 tecken'
	validates_uniqueness_of :title, :message => 'Det finns redan en sida med denna titel'

end
