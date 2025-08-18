# GitHub Actions Workflow Guide

## What Should Happen After Tagging v5.4.4

### 1. Workflow Triggers
The GitHub Actions workflow will trigger on the v5.4.4 tag and run:

- **Unit Tests Job**: Tests the plugin against Koha main, stable, and oldstable
- **Release Job**: Builds the KPZ package and creates a GitHub release

### 2. Expected Workflow Steps

#### Unit Tests (runs in parallel for 3 Koha versions):
1. ✅ Checkout plugin code
2. ✅ Get Koha version branch name
3. ✅ Set up environment variables
4. ✅ Check out Koha
5. ✅ Install koha-testing-docker
6. ✅ Launch KTD instance with plugins support
7. ✅ Wait for KTD to be ready
8. ✅ Install plugins in KTD
9. ✅ Run plugin tests (`prove -v -r -s t/`)
10. ✅ Cleanup KTD instance

#### Release Job (only runs if unit tests pass):
1. ✅ Checkout plugin code
2. ✅ Parse repository name and tag version
3. ✅ Set up Node.js
4. ✅ Install npm dependencies
5. ✅ Run `gulp build` to create KPZ
6. ✅ Create GitHub release with KPZ file

### 3. Expected Outputs

#### If Successful:
- ✅ All tests pass across Koha versions
- ✅ KPZ file created: `koha-plugin-innreach-v5.4.4.kpz`
- ✅ GitHub release created at: `https://github.com/bywatersolutions/koha-plugin-innreach/releases/tag/v5.4.4`
- ✅ Release includes:
  - KPZ file for download
  - README.md
  - Automatic release notes

#### If There Are Issues:
- ❌ Test failures will be shown in the workflow logs
- ❌ Build failures will prevent release creation
- ❌ Logs available at: `https://github.com/bywatersolutions/koha-plugin-innreach/actions`

### 4. How to Monitor

1. **GitHub Actions Tab**: 
   - Go to: `https://github.com/bywatersolutions/koha-plugin-innreach/actions`
   - Look for the workflow run triggered by the v5.4.4 tag

2. **CI Badge**: 
   - The badge in README.md will show current status
   - Green = passing, Red = failing

3. **Releases Page**:
   - Check: `https://github.com/bywatersolutions/koha-plugin-innreach/releases`
   - Should show v5.4.4 release with KPZ download

### 5. Troubleshooting

If the workflow fails:

1. **Check the logs** in GitHub Actions tab
2. **Common issues**:
   - Test failures due to plugin dependencies
   - Build failures in gulp process
   - KTD setup issues
   - Permission issues with releases

3. **Fix and re-tag**:
   ```bash
   # Fix the issue, then:
   git tag -d v5.4.4
   git push origin :refs/tags/v5.4.4
   git tag v5.4.4
   git push origin v5.4.4
   ```

### 6. Next Steps

Once the release is successful:
- ✅ Download and test the KPZ file
- ✅ Update CHANGELOG.md for next version
- ✅ The workflow will run daily to keep the repository active

## Workflow Configuration

The workflow is configured in `.github/workflows/main.yml` and includes:
- Multi-version testing matrix
- Proper plugin installation
- npm/gulp build integration
- Automated release creation
- Keep-alive functionality
