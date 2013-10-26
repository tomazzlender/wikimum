class Page < Sequel::Model

  def before_create
    self.slug = Page.slugify_title(title)
  end

  def before_save
    self.compiled_content = Markup.to_html(self.content)
  end

  def self.search(query)
    terms = query.to_s.strip.split

    return [] if terms.empty?

    columns  = [:title, :content, :description]
    patterns = terms.map {|t| "%#{t}%" }

    self.dataset.grep(columns, patterns, case_insensitive: true, all_patterns: true)
  end

  private

  def self.slugify_title(title)
    regexp = /[^\d\w\sÅÄÖåäö_:-]/i
    title.gsub(regexp, '').gsub(' ', '_')
  end
end
