
lambda { |stdout,stderr,status|
  output = stdout + stderr
  return :green if /All (\d+) tests passed/.match(output)
  return :red   if /Tests failed/.match(output)
  return :amber
}
