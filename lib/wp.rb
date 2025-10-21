require 'mysql2'
require 'digest/md5'

class WP
  def self.cache
    @@cache ||= {}
  end

  def self.db
    # Connect to the database
    @@db ||= Mysql2::Client.new(
      host: ENV['DB_HOST'] || 'localhost',
      username: ENV['DB_USER'],
      password: ENV['DB_PASS'],
      port: ENV['DB_PORT'] || 3306,
      database: ENV['DB_NAME'],
    )
  end

  def self.prefix
    ENV['DB_PREFIX'] || 'wp_'
  end

  # Executes a given MySQL query against the WP database and returns the results.
  # If cache_duration: set to a positive value, caches results for that many seconds.
  def self.query(sql, cache_duration: 0)
    #puts sql # debug
    if (cache_duration > 0) && (cache_key = Digest::MD5.hexdigest(sql)) && (cache_item = cache[cache_key]) && (cache_item[:expiry] > Time.now)
      return cache_item[:value]
    end
    result = db.query(sql)
    (cache[cache_key] = { expiry: Time.now + cache_duration, value: result }) if (cache_duration > 0)
    result
  end

  def self.post_title(post)
    (post['post_title'] == '') ? post['post_name'].gsub('-', ' ').capitalize : post['post_title']
  end

  def self.preview(id)
    query("
      SELECT
        #{prefix}posts.ID, #{prefix}posts.post_date_gmt, #{prefix}posts.post_name, #{prefix}posts.post_title, #{prefix}posts.post_content, #{prefix}postmeta_gemtext.meta_value gemtext
      FROM #{prefix}posts
      LEFT JOIN #{prefix}postmeta #{prefix}postmeta_gemtext ON #{prefix}posts.ID = #{prefix}postmeta_gemtext.post_ID	AND #{prefix}postmeta_gemtext.meta_key='gemtext'
      WHERE #{prefix}posts.ID=#{id.to_i}
      LIMIT 1
    ").to_a[0]
  end

  def self.posts(
    columns: ["#{prefix}posts.ID", "#{prefix}posts.post_date_gmt", "#{prefix}posts.post_name", "#{prefix}posts.post_title", "#{prefix}posts.post_content", "#{prefix}postmeta_gemtext.meta_value gemtext"],
    where: ['(1=1)'],
    order_by: "#{prefix}posts.post_date_gmt DESC",
    limit: 30,
    with_tag: 'published-on-gemini',
    cache_duration: 300
  )
    where << "#{prefix}terms.slug='#{with_tag}'" if with_tag
    where_clauses = where.join(" AND\n ")
    query("
      SELECT
        #{columns.join(', ')}
      FROM #{prefix}terms
      LEFT JOIN #{prefix}term_taxonomy ON #{prefix}terms.term_id = #{prefix}term_taxonomy.term_id
      LEFT JOIN #{prefix}term_relationships ON #{prefix}term_taxonomy.term_taxonomy_id = #{prefix}term_relationships.term_taxonomy_id
      LEFT JOIN #{prefix}posts ON #{prefix}term_relationships.object_id = #{prefix}posts.ID
      LEFT JOIN #{prefix}postmeta #{prefix}postmeta_gemtext ON #{prefix}posts.ID = #{prefix}postmeta_gemtext.post_ID AND #{prefix}postmeta_gemtext.meta_key='gemtext'
      WHERE #{prefix}term_taxonomy.taxonomy='post_tag'
      AND #{prefix}posts.post_type = 'post'
      AND #{prefix}posts.post_status = 'publish'
      AND #{where_clauses}
      ORDER BY #{order_by}
      LIMIT #{limit}
    ", cache_duration: cache_duration).to_a
  end
end
