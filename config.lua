local rs = require 'rs-web'

local highlight_names = { 'Sherlyn P. Wijaya' }
local highlight_class = 'me'

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

local function parse_snippets(content)
  local galleries = {}

  content = content:gsub('<!%-%-.-%-%->', '')
  content = '\n' .. content .. '\n# '

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
      title = title:match '^%s*(.-)%s*$',
      images = {},
    }

    local date_str = section:match '{{date:%s*(%d%d/%d%d)%s*}}'
    if date_str then
      local month, year = date_str:match '(%d%d)/(%d%d)'
      local month_name = month_names[month] or month
      gallery.date_formatted = month_name .. "'" .. year
    end

    for alt, path, img_title in section:gmatch '!%[([^%]]*)%]%(([^%s"]+)%s*"([^"]*)"%)' do
      local rendered_title = img_title
      if img_title and img_title ~= '' then
        rendered_title = rs.render_markdown(img_title)
        rendered_title = rendered_title:gsub('^%s*<p>(.+)</p>%s*$', '%1')
      end
      table.insert(gallery.images, {
        alt = alt,
        src = path,
        title = rendered_title,
      })
    end

    if #gallery.images > 0 then table.insert(galleries, gallery) end

    pos = next_heading
  end

  return galleries
end

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

local phosphor_variants = {
  { name = 'regular', font_name = 'Phosphor', pattern = 'Phosphor' },
  { name = 'fill', font_name = 'Phosphor-Fill', pattern = 'Phosphor%-Fill' },
}

local function start_phosphor_downloads(output_dir)
  local tasks = {}
  local task_info = {}

  for _, variant in ipairs(phosphor_variants) do
    local base_url = 'https://unpkg.com/@phosphor-icons/web@2.1.1/src/' .. variant.name .. '/'

    table.insert(tasks, rs.async.fetch(base_url .. 'style.css', { cache = true }))
    table.insert(task_info, { type = 'css', variant = variant })

    local fonts = { '.woff2', '.woff', '.ttf' }
    for _, ext in ipairs(fonts) do
      table.insert(tasks, rs.async.fetch_bytes(base_url .. variant.font_name .. ext, { cache = true }))
      table.insert(task_info, { type = 'font', name = variant.font_name .. ext })
    end
  end

  return tasks, task_info
end

local function process_phosphor_downloads(results, task_info, output_dir)
  local write_tasks = {}
  local all_css = ''

  for i, resp in ipairs(results) do
    local info = task_info[i]
    if resp and resp.ok then
      if info.type == 'css' then
        local css = resp.body
        local variant = info.variant
        css = css:gsub('url%("%./' .. variant.pattern .. '%.woff2"%)', 'url("/fonts/' .. variant.font_name .. '.woff2")')
        css = css:gsub('url%("%./' .. variant.pattern .. '%.woff"%)', 'url("/fonts/' .. variant.font_name .. '.woff")')
        css = css:gsub('url%("%./' .. variant.pattern .. '%.ttf"%)', 'url("/fonts/' .. variant.font_name .. '.ttf")')
        css = css:gsub('url%("%./' .. variant.pattern .. '%.svg#.-"%)', 'url("/fonts/' .. variant.font_name .. '.svg")')
        all_css = all_css .. css .. '\n'
        rs.print('Fetched Phosphor ' .. variant.name .. ' CSS')
      elseif info.type == 'font' then
        table.insert(write_tasks, rs.async.write(output_dir .. '/fonts/' .. info.name, resp.body))
        rs.print('Fetched ' .. info.name)
      end
    end
  end

  table.insert(write_tasks, rs.async.write_file(output_dir .. '/static/phosphor.css', all_css))

  return write_tasks
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
      rs.async.await_all {
        rs.async.create_dir(ctx.output_dir .. '/fonts'),
        rs.async.create_dir(ctx.output_dir .. '/static'),
      }

      local lexend_task = rs.download_google_font('Lexend', {
        fonts_dir = ctx.output_dir .. '/fonts',
        css_path = ctx.output_dir .. '/static/lexend.css',
        css_prefix = '/fonts',
        weights = { 400, 500, 700 },
        cache = true,
      })
      local phosphor_tasks, phosphor_info = start_phosphor_downloads(ctx.output_dir)

      local all_fetch_tasks = { lexend_task }
      for _, t in ipairs(phosphor_tasks) do
        table.insert(all_fetch_tasks, t)
      end
      local results = rs.async.await_all(all_fetch_tasks)

      local phosphor_results = {}
      for i = 2, #results do
        table.insert(phosphor_results, results[i])
      end
      local write_tasks = process_phosphor_downloads(phosphor_results, phosphor_info, ctx.output_dir)

      table.insert(write_tasks, rs.async.write_file(ctx.output_dir .. '/CNAME', 'sherlyn.pw'))

      rs.async.await_all(write_tasks)

      rs.async.await_all {
        rs.build_css('styles/*.css', ctx.output_dir .. '/static/main.css', { minify = true }),
        rs.async.copy_file('static/avatar.jpg', ctx.output_dir .. '/static/avatar.jpg'),
        rs.async.copy_file('static/cv.pdf', ctx.output_dir .. '/static/cv.pdf'),
      }
      rs.image_convert('static/avatar.jpg', ctx.output_dir .. '/static/avatar.webp', { quality = 85 })

      local function collect_globs(...)
        local out = {}
        for _, pattern in ipairs { ... } do
          local g = rs.glob(pattern) or {}
          for _, v in ipairs(g) do
            table.insert(out, v)
          end
        end
        return out
      end

      local images = collect_globs('site/snippets/**/*.jpg', 'site/snippets/**/*.jpeg', 'site/snippets/**/*.JPG', 'site/snippets/**/*.JPEG')
      rs.print('Found ' .. #images .. ' snippet images')

      local dirs = {}
      local copy_sources = {}
      local copy_dests = {}
      local convert_sources = {}
      local convert_dests = {}

      for _, img in ipairs(images) do
        local img_path = img.path
        local rel_path = img_path:match 'site/snippets/(.+)'
        if rel_path then
          local dir_path = rel_path:match '(.+)/[^/]+$'
          if dir_path then
            table.insert(dirs, ctx.output_dir .. '/snippets/' .. dir_path)
            table.insert(copy_sources, img_path)
            table.insert(copy_dests, ctx.output_dir .. '/snippets/' .. rel_path)
            table.insert(convert_sources, img_path)
            table.insert(convert_dests, ctx.output_dir .. '/snippets/' .. dir_path .. '/' .. img.stem .. '.webp')
          end
        end
      end

      rs.parallel.create_dirs(dirs)
      rs.print('Copying ' .. #copy_sources .. ' images...')
      rs.parallel.copy_files(copy_sources, copy_dests)
      rs.print('Converting ' .. #convert_sources .. ' images to webp...')
      rs.parallel.image_convert(convert_sources, convert_dests, { quality = 85 })
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
