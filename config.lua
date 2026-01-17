local rs = require 'rs-web'

-- Names to highlight
local highlight_names = { 'Sherlyn P. Wijaya' }
local highlight_class = 'me'

-- Transform function to highlight author names
local function highlight_transform(event, ctx)
  if event.type == 'text' and not ctx.in_heading then
    local content = event.content
    local modified = false
    for _, name in ipairs(highlight_names) do
      if string.find(content, name, 1, true) then
        content = string.gsub(content, name, '<span class="' .. highlight_class .. '">%0</span>')
        modified = true
      end
    end
    if modified then
      event.type = 'html'
      event.content = content
    end
  end
  return event
end

-- Month names for date formatting
local month_names = {
  ['01'] = 'Jan',
  ['02'] = 'Feb',
  ['03'] = 'Mar',
  ['04'] = 'Apr',
  ['05'] = 'May',
  ['06'] = 'Jun',
  ['07'] = 'Jul',
  ['08'] = 'Aug',
  ['09'] = 'Sep',
  ['10'] = 'Oct',
  ['11'] = 'Nov',
  ['12'] = 'Dec',
}

-- Parse gallery/snippets from markdown content
-- Format: # Title \n {{date: MM/YY}} \n ![alt](path "title") ...
local function parse_snippets(content)
  local galleries = {}

  -- Remove HTML comments
  content = content:gsub('<!%-%-.-%-%->', '')

  -- Prepend newline so first heading matches, add sentinel at end
  content = '\n' .. content .. '\n# '

  -- Split by headings
  local pos = 1
  while true do
    local title_start = content:find('\n# ', pos)
    if not title_start then break end

    local title_end = content:find('\n', title_start + 3)
    if not title_end then break end

    local title = content:sub(title_start + 3, title_end - 1)

    local next_heading = content:find('\n# ', title_end)
    if not next_heading then break end

    local section = content:sub(title_end, next_heading)

    local gallery = {
      title = title:match '^%s*(.-)%s*$', -- trim
      images = {},
    }

    -- Extract date
    local date_str = section:match '{{date:%s*(%d%d/%d%d)%s*}}'
    if date_str then
      local month, year = date_str:match '(%d%d)/(%d%d)'
      local month_name = month_names[month] or month
      gallery.date_formatted = month_name .. "'" .. year
    end

    -- Extract images: ![alt](path "title")
    for alt, path, img_title in section:gmatch '!%[([^%]]*)%]%(([^%s"]+)%s*"([^"]*)"%)' do
      table.insert(gallery.images, {
        alt = alt,
        src = path,
        title = img_title,
      })
    end

    if #gallery.images > 0 then table.insert(galleries, gallery) end

    pos = next_heading
  end

  return galleries
end

-- Parse news entries from markdown content
-- Format: {MM/YY} Content here...
local function parse_news(content)
  local news = {}
  for date_str, entry_content in content:gmatch '{(%d%d/%d%d)}%s*([^\n]+)' do
    local month, year = date_str:match '(%d%d)/(%d%d)'
    local month_name = month_names[month] or month
    local date_formatted = month_name .. "'" .. year

    table.insert(news, {
      date_raw = date_str,
      date_formatted = date_formatted,
      content = rs.render_markdown(entry_content),
    })
  end
  return news
end

-- Download Phosphor icons (regular + fill) if not already present
local function download_phosphor_icons(output_dir)
  -- Check if already downloaded
  if
    rs.file_exists(output_dir .. '/static/phosphor.css')
    and rs.file_exists(output_dir .. '/fonts/Phosphor.woff2')
    and rs.file_exists(output_dir .. '/fonts/Phosphor-Fill.woff2')
  then
    rs.print 'Phosphor icons already downloaded, skipping'
    return
  end

  local variants = {
    { name = 'regular', font_name = 'Phosphor', pattern = 'Phosphor' },
    { name = 'fill', font_name = 'Phosphor-Fill', pattern = 'Phosphor%-Fill' },
  }

  rs.async.create_dir(output_dir .. '/fonts')
  local all_css = ''

  for _, variant in ipairs(variants) do
    local base_url = 'https://unpkg.com/@phosphor-icons/web@2.1.1/src/' .. variant.name .. '/'
    local css_url = base_url .. 'style.css'

    -- Download CSS
    local css_resp = rs.async.fetch(css_url)
    if css_resp.ok then
      local css = css_resp.body
      -- Replace font URLs with local paths
      css = css:gsub('url%("%./' .. variant.pattern .. '%.woff2"%)', 'url("/fonts/' .. variant.font_name .. '.woff2")')
      css = css:gsub('url%("%./' .. variant.pattern .. '%.woff"%)', 'url("/fonts/' .. variant.font_name .. '.woff")')
      css = css:gsub('url%("%./' .. variant.pattern .. '%.ttf"%)', 'url("/fonts/' .. variant.font_name .. '.ttf")')
      css = css:gsub('url%("%./' .. variant.pattern .. '%.svg#.-"%)', 'url("/fonts/' .. variant.font_name .. '.svg")')
      all_css = all_css .. css .. '\n'
      rs.print('Downloaded Phosphor ' .. variant.name .. ' CSS')

      -- Download font files
      local fonts = { variant.font_name .. '.woff2', variant.font_name .. '.woff', variant.font_name .. '.ttf' }
      for _, font in ipairs(fonts) do
        local font_resp = rs.async.fetch_bytes(base_url .. font)
        if font_resp.ok then
          rs.async.write(output_dir .. '/fonts/' .. font, font_resp.body)
          rs.print('Downloaded ' .. font)
        end
      end
    end
  end

  rs.async.write_file(output_dir .. '/static/phosphor.css', all_css)
end

return {
  site = {
    title = 'Sherlyn P. Wijaya',
    description = 'Personal website of Sherlyn P. Wijaya',
    base_url = rs.env 'SITE_BASE_URL' or 'http://localhost:3000',
    author = 'SPW',
  },

  hooks = {
    before_build = function(ctx)
      -- Download Lexend font if not already present
      if not rs.file_exists(ctx.output_dir .. '/static/lexend.css') then
        rs.download_google_font('Lexend', {
          fonts_dir = ctx.output_dir .. '/fonts',
          css_path = ctx.output_dir .. '/static/lexend.css',
          css_prefix = '/fonts',
          weights = { 400, 500, 700 },
        })
      else
        rs.print 'Lexend font already downloaded, skipping'
      end
      download_phosphor_icons(ctx.output_dir)
      rs.build_css('styles/*.css', ctx.output_dir .. '/static/main.css', { minify = true })
      rs.copy_file('static/avatar.jpg', ctx.output_dir .. '/static/avatar.jpg')
      rs.image_convert('static/avatar.jpg', ctx.output_dir .. '/static/avatar.webp', { quality = 85 })
      rs.copy_file('static/cv.pdf', ctx.output_dir .. '/static/cv.pdf')

      -- CNAME for custom domain
      rs.async.write_file(ctx.output_dir .. '/CNAME', 'sherlyn.pw')

      -- Process snippet images (convert to webp + copy originals)
      -- local images = rs.glob 'site/snippets/**/*.jpg' or {}
      local function collect_globs(...)
        local out = {}
        for _, pattern in ipairs({...}) do
          local g = rs.glob(pattern) or {}
          for _, v in ipairs(g) do table.insert(out, v) end
        end
        return out
      end

      local images = collect_globs(
        'site/snippets/**/*.jpg',
        'site/snippets/**/*.jpeg',
        'site/snippets/**/*.JPG',
        'site/snippets/**/*.JPEG'
      )
      rs.print('Found ' .. #images .. ' snippet images')
      for _, img in ipairs(images) do
        rs.print('Processing: ' .. tostring(img.path))
        local img_path = img.path
        local rel_path = img_path:match 'site/snippets/(.+)'
        if rel_path then
          local dir_path = rel_path:match '(.+)/[^/]+$'
          if dir_path then
            rs.print('Copying to: ' .. ctx.output_dir .. '/snippets/' .. rel_path)
            rs.async.create_dir(ctx.output_dir .. '/snippets/' .. dir_path)
            -- Copy original
            rs.copy_file(img_path, ctx.output_dir .. '/snippets/' .. rel_path)
            -- Convert to webp
            rs.image_convert(img_path, ctx.output_dir .. '/snippets/' .. dir_path .. '/' .. img.stem .. '.webp', { quality = 85 })
          end
        end
      end
    end,
  },

  pages = function(ctx)
    local index = rs.read_frontmatter 'site/index.md'
    local news = rs.read_frontmatter 'site/news.md'
    local snippets = rs.read_frontmatter 'site/snippets.md'
    local contact = rs.read_frontmatter 'site/contact.md'

    return {
      {
        path = '/',
        template = 'page.html',
        title = index.title,
        content = rs.render_markdown(index.content, highlight_transform),
      },
      {
        path = '/news/',
        template = 'news.html',
        title = news.title,
        data = {
          news = parse_news(news.content),
        },
      },
      {
        path = '/snippets/',
        template = 'snippets.html',
        title = snippets.title,
        data = {
          galleries = parse_snippets(snippets.content),
        },
      },
      {
        path = '/contact/',
        template = 'page.html',
        title = contact.title,
        content = rs.render_markdown(contact.content),
      },
    }
  end,
}
