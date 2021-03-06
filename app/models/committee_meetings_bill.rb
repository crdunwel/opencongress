# == Schema Information
#
# Table name: committee_meetings_bills
#
#  id                   :integer          not null, primary key
#  committee_meeting_id :integer
#  bill_id              :integer
#

class CommitteeMeetingsBill < ActiveRecord::Base
  belongs_to :committee_meeting
  belongs_to :bill
end
