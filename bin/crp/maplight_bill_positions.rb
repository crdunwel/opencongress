#!/usr/bin/env ruby

require 'hpricot'
require 'open-uri'

  url = "http://maplight.org/services_open_api/map.bill_list_v1.xml?apikey=#{ApiKeys.maplight}&jurisdiction=us&session=#{Settings.default_congress}&include_organizations=1&has_organizations=1"
  response = Curl.get(url)
    
  rex_doc = REXML::Document.new response.body_str
  elements = rex_doc.elements
  
  elements.each("bills/bill") do |bill_e|
    btype = Bill.govtrack_reverse_lookup(bill_e.elements['prefix'].text.downcase)
    bnumber = bill_e.elements['number'].text.to_i
    bsession = bill_e.elements['session'].text.to_i
    bident = "#{btype}#{bnumber}-#{bsession}"

    bill = Bill.where(:session => bsession, :number => bnumber, :bill_type => btype).first

    if bill
      puts "BILL #{bill.title_full_common}"
      orgs = []
      bigs = []
      bill_e.each_element("organizations/organization") do |org_e|
        org = BillPositionOrganization.find_or_initialize_by_bill_id_and_maplight_organization_id(bill.id, org_e.elements['organization_id'].text)
        org.name = org_e.elements['name'].text
        org.disposition = org_e.elements['disposition'].text
        org.citation = org_e.elements['citation'].text
        org.save 
        
        orgs << org
        unless org_e.elements['disposition'].text.blank? or org_e.elements['catcode'].text.blank?
          ig = CrpInterestGroup.find_by_osid(org_e.elements['catcode'].text)
          if ig
            big = BillInterestGroup.find_or_initialize_by_bill_id_and_crp_interest_group_id(bill.id, ig.id)
            big.disposition = org_e.elements['disposition'].text
            big.save
            
            bigs << big
          end
        end
      end
      
      # scrape interest groups just to make sure
      h = Hpricot(open("#{bill_e.elements["url"].text}/total-contributions.table"))
      
      h.search("div.whom-supported tr > td:first-of-type").each do |g| 
        
        if g.search("a.active").first
          g = g.search("a.active").first
        end
        
        unless g.inner_html.blank?
          ig = CrpInterestGroup.find_by_name(CGI.unescapeHTML(g.inner_html))
          if ig and not bigs.include?(ig)
            puts "SUPPORTS: #{ig.name}"
            big = BillInterestGroup.find_or_initialize_by_bill_id_and_crp_interest_group_id(bill.id, ig.id)
            big.disposition = 'support'
            big.save
          
            bigs << big
          else
            puts "UNKNOWN SUPPORT: #{g.inner_html}"
          end
        end
      end

      h.search("div.whom-opposed tr > td:first-of-type").each do |g| 
        if g.search("a.active").first
          g = g.search("a.active").first
        end

        unless g.inner_html.blank?
        
          ig = CrpInterestGroup.find_by_name(CGI.unescapeHTML(g.inner_html))
          if ig and not bigs.include?(ig)
            puts "OPPOSES: #{ig.name}"
            big = BillInterestGroup.find_or_initialize_by_bill_id_and_crp_interest_group_id(bill.id, ig.id)
            big.disposition = 'oppose'
            big.save
          
            bigs << big
          else
            puts "UNKNOWN OPPOSE: #{g.inner_html}"
          end
        end
      end

      bill.bill_interest_groups = bigs
      bill.bill_position_organizations = orgs
      bill.save
    else
      puts "WARNING: unknown bill: #{bident}"
    end
    
    # adding sleep to try to decrease load on CPU
    sleep(3)
  end
