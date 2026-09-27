export default {
    extends: ['@commitlint/config-conventional'],
    rules: {
        'subject-case': [2, 'never', ['upper-case', 'pascal-case', 'start-case']],
        'type-enum': [
            2,
            'always',
            [
                'feat',
                'fix',
                'docs',
                'style',
                'refactor',
                'perf',
                'test',
                'build',
                'ci',
                'chore',
                'revert',
            ],
        ],
    },
};
