class Commentary < ActiveRecord::Base                              
require 'htmlentities'
  belongs_to :commentariable, :polymorphic => true
  
  has_many :commentary_ratings

  cattr_reader :per_page
  @@per_page = 30

  #decode htmlentities
  def title_d
    d = HTMLEntities.new
    title_d = d.decode(title)
  end

  def excerpt_d
    d = HTMLEntities.new
    excerpt_d = d.decode(excerpt)
  end
  
  def atom_id
    "tag:opencongress.org,#{date.strftime("%Y-%m-%d")}:/commentary/#{id}"
  end

  # Facets

  def type_f
    commentariable_type
  end

  def person_id_f
    person_id
  end

  def bill_id_f
    bill_id
  end

  def is_ok_f
    is_ok
  end

  def is_news_f
    is_news
  end
  
  def thumbsup_count
    commentary_ratings.find(:all, :conditions => "commentary_ratings.rating > 5").length
  end
  
  def score
    if commentary_ratings.count > 0
      score = commentary_ratings.average(:rating)
      unless score == nil
        score = score.round
      end
    return score
    else
      nil
    end
  end
  
  def make_bad
    bc = BadCommentary.new(:url => self.url, :commentariable_id => self.commentariable_id, :commentariable_type => self.commentariable_type, :date => self.date)
    bc.save
    
    self.commentariable.decrement!(self.is_news ? :news_article_count : :blog_article_count)
    
    self.destroy
  end
  
  def article_valid?
    # first try to match a term in the title or exceprt
    @@VALIDATING_TERMS.each do |t|
      if ((self.title && self.title.match(/#{t}/i)) || 
          (self.excerpt && self.excerpt.match(/#{t}/i)))
        self.contains_term = t
        #puts "Matched in title/excerpt.  Not going to external page."
        return true
      end
    end
    
    # if we got here, we need to check the full text of the article
    num_redirects = 3
    begin
      response = nil
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host)
      http.start do |http|
        request = Net::HTTP::Get.new(uri.request_uri, {"User-Agent" => @@USERAGENT})
        response = http.request(request)
      end

      #puts "response #{response.code}"
      while response.kind_of?(Net::HTTPRedirection)
        num_redirects -= 1
    
        return false if (num_redirects == 0)
        uri = URI.parse(response['location'])
        http = Net::HTTP.new(uri.host)
        http.start do |http|
          request = Net::HTTP::Get.new(uri.request_uri, {"User-Agent" => @@USERAGENT})
          response = http.request(request)
        end
        #puts "response #{response.code}"
      end
        
      if response.kind_of?(Net::HTTPSuccess)
        @@VALIDATING_TERMS.each do |t|
          if response.body.match(/#{t}/i)
            self.contains_term = t
            return true
          end
        end
      end
    rescue TimeoutError
      logger.warn "Timeout trying to validate article: #{url}!"
      return false
    rescue Exception
      logger.warn "Error trying to validate article: #{url}: #{$!}"
    end
    
    false
  end
  
  def senate_bill_strict_validity
    # we don't want 'S.123' to match things like this: "..roadside bombs. 123 more were killed..."
    if (/\w*['|(&#8217;)]?s(\.)?(\s)*#{self.commentariable.number}/.match("#{self.excerpt} #{self.title}"))
      #puts "BAD! (#{b.typenumber}) #{c.excerpt} TITLE: #{c.title}"
      return 'FALSE POSITIVE'
    else
      # at least make sure we match 'S.123' or 'S. 123'
      if (/\s?S\.( )?#{self.commentariable.number}[:\s]/.match("#{self.excerpt} #{self.title}"))
        #puts "SEEMS GOOD! (#{b.typenumber}) #{c.excerpt} TITLE: #{c.title}"
        return 'OK'
      # make things that match 'S 123' pending
      elsif (/S( )?#{self.commentariable.number}/.match("#{self.excerpt} #{self.title}"))
        #puts "POSSIBLE! (#{b.typenumber}) #{c.excerpt} TITLE: #{c.title}"
        return 'PENDING'
      else
        #puts "BAD! (#{b.typenumber}) #{c.excerpt} TITLE: #{c.title}"      
        return 'FALSE POSITIVE'         
      end
    end
  end
  
  @@USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'
  @@VALIDATING_TERMS = [ 
    "congress",  
    "congressman", 
    "congresswoman", 
    "congressperson",
    "democrat",
    "republican",
    "senate",
    "house of representatives", 
    "senator", 
    "representative",
    "sen\\.", 
    "rep\\.",
    "introduced bill",
    "roll call",
    "legislation",
    "legislative"
  ]
end
