############################################################################
# Copyright 2009,2010 Benjamin Kellermann                                  #
#                                                                          #
# This file is part of dudle.                                              #
#                                                                          #
# Dudle is free software: you can redistribute it and/or modify it under   #
# the terms of the GNU Affero General Public License as published by       #
# the Free Software Foundation, either version 3 of the License, or        #
# (at your option) any later version.                                      #
#                                                                          #
# Dudle is distributed in the hope that it will be useful, but WITHOUT ANY #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or        #
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public     #
# License for more details.                                                #
#                                                                          #
# You should have received a copy of the GNU Affero General Public License #
# along with dudle.  If not, see <http://www.gnu.org/licenses/>.           #
############################################################################

require "hash"
require "yaml"
require "time"
require "pollhead"
require "timepollhead"

$KCODE = "u"
class String
	def to_htmlID
		CGI.escapeHTML(self.gsub(/[^A-Za-z0-9_:.\-]/,"."))
	end
end
class Poll
	attr_reader :head, :name
	YESVAL   = "ayes"
	MAYBEVAL = "bmaybe"
	NOVAL    = "cno"
	def initialize name,type
		@name = name

		case type
		when "normal"
			@head = PollHead.new
		when "time"
			@head = TimePollHead.new
		else
			raise("unknown poll type: #{type}")
		end
		@data = {}
		@comment = []
		store "Poll #{name} created"
	end

	def sort_data fields
		if fields.include?("name")
			until fields.pop == "name"
			end
			@data.sort{|x,y|
				cmp = x[1].compare_by_values(y[1],fields) 
				cmp == 0 ? x[0].downcase <=> y[0].downcase : cmp
			}
		else
			@data.sort{|x,y| x[1].compare_by_values(y[1],fields)}
		end
	end

	def userstring(participant,link)
		ret = ""
		if link
			ret += "<td><span class='edituser'>"
			ret += "<a title='" 
			ret += _("Edit user %{user}...") % {:user => CGI.escapeHTML(participant)} 
			ret += "' href=\"?edituser=#{CGI.escapeHTML(CGI.escape(participant))}\">" 
			ret += EDIT
			ret += "</a> | <a title='" 
			ret += _("Delete user %{user}...") % {:user => CGI.escapeHTML(participant)} 
			ret += "' href=\"?deleteuser&amp;edituser=#{CGI.escapeHTML(CGI.escape(participant))}\">" 
			ret += "#{DELETE}</a>"
			ret += "</span></td>"
			ret += "<td class='name'>"
		else
			ret += "<td class='invisible'></td><td class='name'>"
		end
		ret += participant
		ret += "</td>"
		ret
	end
	def to_html(showparticipation = true)
		ret = "<table border='1'>\n"
		
		sortcolumns = $cgi.include?("sort") ? $cgi.params["sort"] : ["timestamp"]
		ret += @head.to_html(sortcolumns)
		sort_data(sortcolumns).each{|participant,poll|
			if $cgi["edituser"] == participant
				ret += participate_to_html
			else
				ret += "<tr class='participantrow'>\n"
				ret += userstring(participant,showparticipation)
				@head.columns.each{|column|
					klasse = poll[column]
					case klasse
					when nil
						value = UNKNOWN
						klasse = "undecided"
					when YESVAL
						value = YES
					when NOVAL
						value = NO
					when MAYBEVAL
						value = MAYBE
					end
					ret += "<td class='#{klasse}' title=\"#{CGI.escapeHTML(participant)}: #{CGI.escapeHTML(column.to_s)}\">#{value}</td>\n"
				}
				ret += "<td class='date'>#{poll['timestamp'].strftime('%d.%m,&nbsp;%H:%M')}</td>"
				ret += "</tr>\n"
			end
		}

		# PARTICIPATE
		ret += participate_to_html unless @data.keys.include?($cgi["edituser"]) || !showparticipation

		# SUMMARY
		ret += "<tr id='summary'><td colspan='2' class='name'>" + _("Total") + "</td>\n"
		@head.columns.each{|column|
			yes = 0
			undecided = 0
			@data.each_value{|participant|
				if participant[column] == YESVAL
					yes += 1
				elsif !participant.has_key?(column) or participant[column] == MAYBEVAL
					undecided += 1
				end
			}

			if @data.empty?
				percent_f = 0
			else
				percent_f = 100*yes/@data.size
			end
			percent = "#{percent_f}%" unless @data.empty?
			if undecided > 0
				percent += "-#{(100.0*(undecided+yes)/@data.size).round}%"
			end

			ret += "<td id='sum_#{column.to_htmlID}' class='sum' title='#{percent}' style='"
			["","background-"].each {|c|
				ret += "#{c}color: rgb("
				3.times{ 
					ret += (c == "" ? "#{155+percent_f}" : "#{100-percent_f}")
					ret += ","
				}
				ret.chop!
				ret += ");"
			}
			ret += "'>#{yes}</td>\n"
		}

		ret += "<td class='invisible'></td></tr>"
		ret += "</table>\n"
		ret
	end

	def invite_to_html
		edituser = $cgi["edituser"] unless $cgi.include?("deleteuser")
		invitestr = _("Invite")
		namestr = _("Name")
		ret = <<HEAD
<table id='participanttable' class='settingstable'>
<tr>
	<th colspan='2'>#{namestr}</th>
</tr>
HEAD
		@data.keys.sort.each{|participant|
			has_voted = false
			@head.columns.each{|column|
				has_voted = true unless @data[participant][column].nil?
			}

			if edituser == participant
				ret += "<tr id='add_participant'>"
				ret += add_participant_input(edituser)
				ret += save_input(edituser,invitestr)
			else
				ret += "<tr class='participantrow'>"
				ret += userstring(participant,!has_voted)
			end
			ret += "</tr>"

		}
		unless @data.keys.include?(edituser)
			ret += "<tr id='add_participant'>"
			ret += add_participant_input(edituser)
			ret += save_input(edituser,invitestr)
			ret += "</tr>"
		end
		ret += "</table>"
		ret
	end
	def add_participant_input(edituser)
		return <<END
<td colspan='2' id='add_participant_input_td'>
	<input type='hidden' name='olduser' value=\"#{edituser}\" />
	<input size='16' 
		type='text' 
		name='add_participant'
		id='add_participant_input'
		value="#{edituser}"/>
</td>
END
	end
	def save_input(edituser, savestring, changestr = _("Save Changes"))
		ret = "<td>"
		if @data.include?(edituser)
			ret += "<input id='savebutton' type='submit' value='#{changestr}' />"
			ret += "<br /><input style='margin-top:1ex' type='submit' name='cancel' value='" + _("Cancel") + "' />"
		else
			ret += "<input id='savebutton' type='submit' value='#{savestring}' />"
		end
		ret += "</td>\n"
	end

	def participate_to_html
		ret = "<tr id='separator_top'><td colspan='#{@head.col_size + 3}' class='invisible'></td></tr>\n"

		if $cgi.include?("deleteuser") && @data.include?($cgi["edituser"])
			ret += deleteuser_to_html
		else
			ret += edituser_to_html
		end
		ret += "<tr id='separator_bottom'><td colspan='#{@head.col_size + 3}' class='invisible'></td></tr>\n"
	end

	def deleteuser_to_html
		ret = "<tr id='add_participant'>\n"
		ret += "<td colspan='2' class='name'>#{$cgi["edituser"]}</td>"
		ret += "<td colspan='#{@head.col_size}'>"
		ret += _("Do you really want to delete user %{user}?") % {:user => $cgi["edituser"]}
		ret += "<input type='hidden' name='delete_participant_confirm' value='#{$cgi["edituser"]}' />"
		ret += "</td>"
		ret += save_input($cgi["edituser"], "", _("Confirm"))
		ret += "</tr>"
		ret
	end

	def edituser_to_html
		edituser = $cgi["edituser"]
		checked = {}
		if @data.include?(edituser)
			@head.columns.each{|k| checked[k] = @data[edituser][k]}
		else
			edituser = $cgi.cookies["username"][0] unless @data.include?($cgi.cookies["username"][0])
			@head.columns.each{|k| checked[k] = NOVAL}
		end

		ret = "<tr id='add_participant'>\n"

		ret += add_participant_input(edituser)

		@head.columns.each{|column|
			ret += "<td class='checkboxes'><table class='checkboxes'>"
			[[YES, YESVAL],[NO, NOVAL],[MAYBE, MAYBEVAL]].each{|valhuman, valbinary|
				ret += <<TR
				<tr class='input-#{valbinary}'>
					<td class='input-#{valbinary}'>
						<input type='radio' 
							value='#{valbinary}' 
							id=\"add_participant_checked_#{column.to_htmlID}_#{valbinary}\" 
							name=\"add_participant_checked_#{CGI.escapeHTML(column.to_s)}\" 
							title=\"#{CGI.escapeHTML(column.to_s)}\" #{checked[column] == valbinary ? "checked='checked'":""}/>
					</td>
					<td class='input-#{valbinary}'>
						<label for=\"add_participant_checked_#{column.to_htmlID}_#{valbinary}\">#{valhuman}</label>
					</td>
			</tr>
TR
			}
			ret += "</table></td>"
		}
		ret += save_input(edituser, _("Save"))

		ret += "</tr>\n"

		ret
	end

	def comment_to_html(editable = true)
		ret = "<div id='comments'>"
		ret	+= "<h2>" + _("Comments") + "</h2>" if !@comment.empty? || editable

		unless @comment.empty?
			@comment.each_with_index{|c,i|
				time,name,comment = c
				ret += "<form method='post' action='.'>"
				ret += "<div class='textcolumn'><h3 class='comment'>"
				ret += _("%{user} said on %{time}") % {:user => name, :time => time.strftime("%d.%m., %H:%M")}
				if editable
					ret += "<input type='hidden' name='delete_comment' value='#{i}' />"
					ret += "&nbsp;"
					ret += "<input class='delete_comment_button' type='submit' value='"
					ret += _("Delete")
					ret += "' />"
				end
				ret += "</h3>#{comment}</div>"
				ret += "</form>"
			}
		end
		
		if editable
			# ADD COMMENT
			saysstr = _("says")
			submitstr = _("Submit Comment")
			ret += <<ADDCOMMENT
<form method='post' action='.' accept-charset='utf-8'>
	<div class='comment' id='add_comment'>
		<input value='#{$cgi.cookies["username"][0] || "Anonymous"}' type='text' name='commentname' size='9' /> #{saysstr}&nbsp;
		<br />
		<textarea cols='50' rows='7' name='comment' ></textarea>
		<br /><input type='submit' value='#{submitstr}' />
	</div>
</form>
ADDCOMMENT
		end

		ret += "</div>\n"
		ret
	end

	def history_selectform(revision, selected)
		showhiststr = _("Show history items:")
		ret = <<FORM
<form method='get' action=''>
	<div>
		#{showhiststr} 
		<select name='history'>
FORM
		[["",_("All")],
		 ["participants",_("Participant related")],
		 ["columns",_("Column related")],
		 ["comments",_("Comment related")],
		 ["ac",_("Access Control related")]
			].each{|value,opt|
			ret += "<option value='#{value}' #{selected == value ? "selected='selected'" : ""} >#{opt}</option>"
		}
		ret += "</select>"
		ret += "<input type='hidden' name='revision' value='#{revision}' />" if revision
		updatestr = _("Update")
		ret += <<FORM
		<input type='submit' value='#{updatestr}' />
	</div>
</form>
FORM
		ret
	end

	def history_to_html(middlerevision,only)
		log = VCS.history
		if only != ""
			case only
			when "comments"
				match = /^Comment .*$/
			when "participants"
				match = /^Participant .*$/
			when "columns"
				match = /^Column .*$/
			when "ac"
				match = /^Access Control .*$/
			else
				raise "invalid value #{only}"
			end
			log = log.comment_matches(match)
		end
		log.around_rev(middlerevision,11).to_html(middlerevision,only)
	end

	def add_participant(olduser, name, agreed)
		name.strip!
		if name == ""
			maximum = @data.keys.collect{|e| e.scan(/^Anonymous #(\d*)/).flatten[0]}.compact.collect{|i| i.to_i}.max
			maximum ||= 0
			name = "Anonymous ##{maximum + 1}"
		end
		htmlname = CGI.escapeHTML(name)
		action = ''
		if @data.delete(CGI.escapeHTML(olduser))
			action = "edited"
		else
			action = "added"
		end
		@data[htmlname] = {"timestamp" => Time.now }
		@head.columns.each{|column|
			@data[htmlname][column] = agreed[column.to_s]
		}
		store "Participant #{name.strip} #{action}"
	end

	def delete(name)
		htmlname = CGI.escapeHTML(name.strip)
		if @data.has_key?(htmlname)
			@data.delete(htmlname)
			store "Participant #{name.strip} deleted"
		end
	end

	def store comment
		File.open("data.yaml", 'w') do |out|
			out << "# This is a dudle poll file\n"
			out << self.to_yaml
			out.chmod(0660)
		end
		VCS.commit(CGI.escapeHTML(comment))
	end

	###############################
	# comment related functions 
	###############################
	def add_comment name, comment
		@comment << [Time.now, CGI.escapeHTML(name.strip), CGI.escapeHTML(comment.strip).gsub("\r\n","<br />")]
		store "Comment added by #{name}"
	end

	def delete_comment index
		store "Comment from #{@comment.delete_at(index)[1]} deleted"
	end

	###############################
	# column related functions
	###############################
	def delete_column column
		if @head.delete_column(column)
			store "Column #{column} deleted"
			return true
		else
			return false
		end
	end

	def edit_column(oldcolumn, newtitle, cgi)
		parsedtitle = @head.edit_column(oldcolumn, newtitle, cgi)
		store "Column #{parsedtitle} #{oldcolumn == "" ? "added" : "edited"}" if parsedtitle
	end

	def edit_column_htmlform(activecolumn, revision)
		@head.edit_column_htmlform(activecolumn, revision)
	end
end

if __FILE__ == $0
require 'test/unit'
require 'cgi'
require 'pp'

SITE = "glvhc_8nuv_8fchi09bb12a-23_uvc"
class Poll
	attr_accessor :head, :data, :comment
	def store comment
	end
end
#┌───────────────────┬─────────────────────────────────┬────────────┐
#│                   │            May 2009             │            │
#├───────────────────┼────────┬────────────────────────┼────────────┤
#│                   │Tue, 05 │        Sat, 23         │            │
#├───────────────────┼────────┼────────┬────────┬──────┼────────────┤
#│      Name ▾▴      │   ▾▴   │10:00 ▾▴│11:00 ▾▴│foo ▾▴│Last Edit ▾▴│
#├───────────────────┼────────┼────────┼────────┼──────┼────────────┤
#│Alice ^✍           │✔       │✘       │✔       │✘     │24.11, 18:15│
#├───────────────────┼────────┼────────┼────────┼──────┼────────────┤
#│Bob ^✍             │✔       │✔       │✘       │?     │24.11, 18:15│
#├───────────────────┼────────┼────────┼────────┼──────┼────────────┤
#│Dave ^✍            │✘       │?       │✔       │✔     │24.11, 18:16│
#├───────────────────┼────────┼────────┼────────┼──────┼────────────┤
#│Carol ^✍           │✔       │✔       │?       │✘     │24.11, 18:16│
#├───────────────────┼────────┼────────┼────────┼──────┼────────────┤
#│total              │3       │2       │2       │1     │            │
#└───────────────────┴────────┴────────┴────────┴──────┴────────────┘

class PollTest < Test::Unit::TestCase
	Y,N,M   = Poll::YESVAL, Poll::NOVAL, Poll::MAYBEVAL
	A,B,C,D = "Alice", "Bob", "Carol", "Dave"
	Q,W,E,R = "2009-05-05", "2009-05-23 10:00", "2009-05-23 11:00", "2009-05-23 foo"
	def setup
		def add_participant(type,user,votearray)
			h = { Q => votearray[0], W => votearray[1], E => votearray[2], R => votearray[3]}
			@polls[type].add_participant("",user,h)
		end

		@polls = {}
		["time","normal"].each{|type|
			@polls[type] = Poll.new(SITE, type)

			@polls[type].edit_column("","2009-05-05", {"columndescription" => ""})
			2.times{|t|
				@polls[type].edit_column("","2009-05-23 #{t+10}:00", {"columntime" => "#{t+10}:00","columndescription" => ""})
			}
			@polls[type].edit_column("","2009-05-23 foo", {"columntime" => "foo","columndescription" => ""})


			add_participant(type,A,[Y,N,Y,N])
			add_participant(type,B,[Y,Y,N,M])
			add_participant(type,D,[N,M,Y,Y])
			add_participant(type,C,[Y,Y,M,N])
		}
	end
	def test_sort
		["time","normal"].each{|type|
			comment = "Test Type: #{type}"
			assert_equal([A,B,C,D],@polls[type].sort_data(["name"]).collect{|a| a[0]},comment)
			assert_equal([A,B,D,C],@polls[type].sort_data(["timestamp"]).collect{|a| a[0]},comment)
			assert_equal([B,C,D,A],@polls[type].sort_data([W,"name"]).collect{|a| a[0]},comment)
			assert_equal([B,A,C,D],@polls[type].sort_data([Q,R,E]).collect{|a| a[0]},comment+ " " + [Q,R,E].join("; "))
		}
	end
end

end
