require 'rubygems'
require 'fastercsv'

# To prepare PowerSchool export files:
#
# 1. Select all students. 
# 2. Export with "Names-Families-All-Contact-Info" template to "students.txt".
# 3. Select staff with "status=1;staffstatus#0". 
# 4. Export with "USNetcom-Staff" template to "staff.txt".

class PhoneExporter
  
  GOOD_AREA_CODES = [ '800', '415', '510', '650', '707', '925', '408' ]

  STUDENT_PHONE_FIELDS = [
    [ :home_phone, '1h', 'home' ],
    [ :home2_phone, '1h', 'home' ],
    [ :mother_work_phone, '1m', 'work' ],
    [ :father_work_phone, '1f', 'work' ],
    [ :mother2_work_phone, '2m', 'work' ],
    [ :father2_work_phone, '2f', 'work' ],
    [ :mother_cell, '1m', 'cell' ],
    [ :father_cell, '1f', 'cell' ],
    [ :mother2_cell, '2m', 'cell' ],
    [ :father2_cell, '2f', 'cell' ],
  ]

  FACULTY_PHONE_FIELDS = [
    [ :home_phone, 'home' ],
    [ :school_phone, 'work' ],
    [ :cell, 'cell' ]
  ]

  PARENT_NAME_FIELDS = {
    '1m' => [ :mother_first, :mother ], 
    '1f' => [ :father_first, :father ],
    '2m' => [ :mother2_first, :mother2_last ], 
    '2f' => [ :father2_first, :father2_last ]
  }

  FAMILY_NAME_KEYS = [ [ '1m', '1f' ], [ '2m', '2f'] ] 
  
  def initialize
    @k_recs = { }
    @b_recs = { }
  end

  def get_phone(s, all_area_codes=false)
    return nil if s.nil?
    s.strip!
    return nil if s.empty?

    # just fail if phones start with + (international)
    # just fail if phones have x888 (emergency dialer can't handle extensions)
    return "?int #{s}" if s.match(/^\+/) 
    return "?ext #{s}" if s.match(/x[0-9]+$/)

    unless s.match(/[0-9]/)
      # no numbers, forget it
      return "?fmt #{s}" 
    end
  
    # get 1 + 10 digits
    slen = s.length
    start = 0
    pos = 0
    dcount10 = 10
    dcount7 = 7
    if s[0, 1] == '1'
      start = 1
      pos = 1
    end
    pos10 = nil
    pos7 = nil
    stop = false
    while pos < slen && dcount10 > 0
      ch = s[pos, 1]
      if ch.match(/[0-9]/)
        dcount10 -= 1
        dcount7 -= 1
      elsif !pos7.nil? && ch != '-'
        break
      end
      pos += 1
      if dcount10 == 0
        pos10 = pos
      end
      if dcount7 == 0
        pos7 = pos
      end
    end

    if !pos10.nil?
      if pos10 < slen
        extra = s[pos10, slen-pos10]
        if extra.match(/[#x]/)
          return "?ext #{s}"
        end
      end
      s_num = s[start, pos10].gsub(/[^0-9]/, '')
      area_code = s_num[0, 3]
      # STDERR.print "10digit: #{s}\n"
      s = "(#{area_code}) #{s_num[3, 3]}-#{s_num[6, 4]}"
      return "?lds #{s}" if !all_area_codes && !GOOD_AREA_CODES.include?(area_code)
      return s
    end

    if !pos7.nil?
      if pos7 < slen
        extra = s[pos7, slen-pos7]
        if extra.match(/[#x]/)
          return "?ext #{s}"
        end
      end
      s_num = s[start, pos7].gsub(/[^0-9]/, '')
      # STDERR.print "7digit: #{s}\n"
      return "(415) #{s_num[0, 3]}-#{s_num[3, 4]}"
    end
  
    # wrong number(s)
    return "?len #{s}"
  end

  def get_phones(s, all_area_codes=false) 
    return [] if s.nil?
    s.strip!
    return [] if s.empty?
  
    if s.match(/\Wor\W/)
      phones = []
      more = s.split(/or/)
      for s in more
        phones.push(get_phone(s, all_area_codes))
      end
      return phones
    end

    return [get_phone(s, all_area_codes)]
  end

  def get_name(row, who)
    if who[1, 1] == 'h'
      family_num = who[0, 1].to_i
      # print "home fn: #{family_num}\n"
      for who in FAMILY_NAME_KEYS[family_num-1] do
        ffirst, flast = PARENT_NAME_FIELDS[who]
        # print "name fields: #{ffirst}, #{flast}\n"
        name = "#{row[ffirst]} #{row[flast]}".gsub(/,/, '').strip
        return name unless name.empty?
      end
    else
      # print "who: #{who}\n"
      ffirst, flast = PARENT_NAME_FIELDS[who]
      # print "name fields: #{ffirst}, #{flast}\n"
      name = "#{row[ffirst]} #{row[flast]}".gsub(/,/, '').strip
      return name unless name.empty?
    end
    # print "falling back to student name for #{who}\n"
    return "#{row['first_name']} #{row['last_name']}".gsub(/,/, '').strip
  end

  def get_school(schoolid)
    schoolid = 102 if schoolid.nil?
    schoolid = schoolid.to_i
    case schoolid
    when 103
      :bacich
    when 104
      :kent
    else
      :district
    end
  end

  def print_phones(fname, school)
    h = (school.to_sym == :bacich) ? @b_recs : @k_recs
    f = File.new(fname, 'wb')
    f.print "phone,id,name,school,grade,who,which\n"
    keys = h.keys.sort
    keys.each do |ph|
      if ph.match(/^\?/)
        STDERR.print h[ph]
      else
        f.print h[ph]
      end
    end
    f.close
  end

  def import_students(fname)
    FasterCSV.foreach(fname, :col_sep => "\t", :row_sep => "\n", :headers => true,
      :header_converters => :symbol) do |row|
      id = row[:student_number]
      school = get_school(row[:schoolid])
      grade = row[:grade_level]
      grade = 'k' if grade == '0'
      STUDENT_PHONE_FIELDS.each do |field|
        key, who, which = field
        family_num = who[0, 1].to_i
        all_codes = (family_num == 1)
        phones = get_phones(row[key], all_codes)
        for ph in phones
          name = get_name(row, who)
          line = "#{ph},#{id},#{name},#{school},#{grade},#{who},#{which}\n"
          if school == :kent
            @k_recs[ph] = line
          elsif school == :bacich
            @b_recs[ph] = line
          else
            # ignore record for NPS students, etc.
          end
        end
      end
    end
  end

  def import_staff(fname)
    FasterCSV.foreach(fname, :col_sep => "\t", :row_sep => "\n", :headers => true,
      :header_converters => :symbol) do |row|
      id = row[:teachernumber]
      school = get_school(row[:schoolid])
      all_sites = row[:all_sites] == '1'
      name = "#{row[:first_name]} #{row[:last_name]}".gsub(/,/, '').strip
      FACULTY_PHONE_FIELDS.each do |field|
        key, which = field
        phones = get_phones(row[key], true)
        for ph in phones
          line = "#{ph},#{id},#{name},#{school},,staff,#{which}\n"
          if all_sites || (school == :kent)
            @k_recs[ph] = line
          end
          if all_sites || (school == :bacich)
            @b_recs[ph] = line
          end
        end
      end
    end
  end
end

pe = PhoneExporter.new
pe.import_students('students.txt')
pe.import_staff('staff.txt')
pe.print_phones('usnetcom_bacich.csv', :bacich)
pe.print_phones('usnetcom_kent.csv', :kent)

