// Jest Configuration Template for React/Node.js Applications
// Comprehensive testing setup with coverage, mocking, and performance optimization

module.exports = {
  // Test environment
  testEnvironment: 'jsdom',
  
  // Setup files
  setupFilesAfterEnv: [
    '<rootDir>/src/setupTests.js',
    '<rootDir>/src/testUtils/globalSetup.js'
  ],
  
  // Module paths
  roots: ['<rootDir>/src'],
  modulePaths: ['<rootDir>/src'],
  
  // Module name mapping for absolute imports
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@components/(.*)$': '<rootDir>/src/components/$1',
    '^@utils/(.*)$': '<rootDir>/src/utils/$1',
    '^@services/(.*)$': '<rootDir>/src/services/$1',
    '^@hooks/(.*)$': '<rootDir>/src/hooks/$1',
    '^@store/(.*)$': '<rootDir>/src/store/$1',
    '^@assets/(.*)$': '<rootDir>/src/assets/$1',
    
    // Handle CSS and asset imports
    '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    '\\.(jpg|jpeg|png|gif|eot|otf|webp|svg|ttf|woff|woff2|mp4|webm|wav|mp3|m4a|aac|oga)$': 
      '<rootDir>/src/testUtils/fileMock.js'
  },
  
  // File extensions to consider
  moduleFileExtensions: [
    'js',
    'jsx',
    'ts',
    'tsx',
    'json',
    'node'
  ],
  
  // Transform files
  transform: {
    '^.+\\.(js|jsx|ts|tsx)$': ['babel-jest', {
      presets: [
        ['@babel/preset-env', { targets: { node: 'current' } }],
        ['@babel/preset-react', { runtime: 'automatic' }],
        '@babel/preset-typescript'
      ],
      plugins: [
        '@babel/plugin-proposal-class-properties',
        '@babel/plugin-transform-runtime'
      ]
    }]
  },
  
  // Files to ignore during transformation
  transformIgnorePatterns: [
    'node_modules/(?!(axios|@testing-library|react-router)/)'
  ],
  
  // Test match patterns
  testMatch: [
    '<rootDir>/src/**/__tests__/**/*.{js,jsx,ts,tsx}',
    '<rootDir>/src/**/*.(test|spec).{js,jsx,ts,tsx}'
  ],
  
  // Files to ignore
  testPathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/build/',
    '<rootDir>/dist/'
  ],
  
  // Coverage configuration
  collectCoverage: true,
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/index.js',
    '!src/serviceWorker.js',
    '!src/reportWebVitals.js',
    '!src/**/*.stories.{js,jsx,ts,tsx}',
    '!src/testUtils/**',
    '!src/mocks/**',
    '!src/**/*.mock.{js,jsx,ts,tsx}'
  ],
  
  // Coverage thresholds
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    },
    './src/components/': {
      branches: 85,
      functions: 85,
      lines: 85,
      statements: 85
    },
    './src/utils/': {
      branches: 90,
      functions: 90,
      lines: 90,
      statements: 90
    }
  },
  
  // Coverage reporters
  coverageReporters: [
    'text',
    'text-summary',
    'html',
    'lcov',
    'json',
    'cobertura'
  ],
  
  // Coverage directory
  coverageDirectory: '<rootDir>/coverage',
  
  // Global variables
  globals: {
    'ts-jest': {
      tsconfig: 'tsconfig.json'
    }
  },
  
  // Test timeout
  testTimeout: 10000,
  
  // Verbose output
  verbose: true,
  
  // Clear mocks between tests
  clearMocks: true,
  
  // Restore mocks after each test
  restoreMocks: true,
  
  // Error on deprecated features
  errorOnDeprecated: true,
  
  // Notify mode
  notify: false,
  
  // Watch plugins
  watchPlugins: [
    'jest-watch-typeahead/filename',
    'jest-watch-typeahead/testname'
  ],
  
  // Reporters
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: '<rootDir>/test-results',
      outputName: 'junit.xml',
      ancestorSeparator: ' › ',
      uniqueOutputName: 'false',
      suiteNameTemplate: '{filepath}',
      classNameTemplate: '{classname}',
      titleTemplate: '{title}'
    }],
    ['jest-html-reporters', {
      publicPath: '<rootDir>/test-results',
      filename: 'test-report.html',
      expand: true
    }]
  ],
  
  // Performance optimization
  maxWorkers: '50%',
  
  // Cache directory
  cacheDirectory: '<rootDir>/node_modules/.cache/jest',
  
  // Projects for multi-project setup
  projects: [
    {
      displayName: 'unit',
      testMatch: ['<rootDir>/src/**/*.test.{js,jsx,ts,tsx}'],
      testEnvironment: 'jsdom'
    },
    {
      displayName: 'integration',
      testMatch: ['<rootDir>/src/**/*.integration.test.{js,jsx,ts,tsx}'],
      testEnvironment: 'node'
    }
  ]
};

